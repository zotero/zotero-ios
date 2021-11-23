//
//  DebugLogging.swift
//  Zotero
//
//  Created by Michal Rentka on 04/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

protocol DebugLoggingCoordinator: AnyObject {
    func createDebugAlertActions() -> ((Result<(String, String?), DebugLogging.Error>, [URL]?, (() -> Void)?, (() -> Void)?) -> Void, (Double) -> Void)
    func show(error: DebugLogging.Error, logs: [URL]?, retry: (() -> Void)?, completed: (() -> Void)?)
    func setDebugWindow(visible: Bool)
}

fileprivate struct PendingCoordinatorAction {
    let ignoreEmptyLogs: Bool
    let customAlertMessage: ((String) -> String)?
}

final class DebugLogging {
    enum LoggingType {
        case immediate
        case nextLaunch
    }

    enum Error: Swift.Error {
        case start
        case contentReading
        case noLogsRecorded
        case upload
        case responseParsing
        case cantCreateData
    }

    private unowned let apiClient: ApiClient
    private unowned let fileStorage: FileStorage
    let isEnabledPublisher: PublishSubject<Bool>
    private let queue: DispatchQueue
    private let scheduler: ConcurrentDispatchQueueScheduler
    private let disposeBag: DisposeBag

    @UserDefault(key: "IsDebugLoggingEnabled", defaultValue: false)
    private(set) var isEnabled: Bool {
        didSet {
            self.coordinator?.setDebugWindow(visible: self.isEnabled)
            self.isEnabledPublisher.on(.next(self.isEnabled))
        }
    }
    private(set) var didStartFromLaunch: Bool
    private var logger: DDFileLogger?
    weak var coordinator: DebugLoggingCoordinator? {
        didSet {
            guard let action = self.pendingAction else { return }
            self.queue.async { [weak self] in
                self?.shareLogs(ignoreEmptyLogs: action.ignoreEmptyLogs, customAlertMessage: action.customAlertMessage)
                self?.logger = nil
            }
        }
    }
    private var pendingAction: PendingCoordinatorAction?

    init(apiClient: ApiClient, fileStorage: FileStorage) {
        let queue = DispatchQueue(label: "org.zotero.DebugLogging.Queue", qos: .userInitiated)
        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.queue = queue
        self.didStartFromLaunch = false
        self.isEnabledPublisher = PublishSubject()
        self.scheduler = ConcurrentDispatchQueueScheduler(queue: queue)
        self.disposeBag = DisposeBag()
    }

    func start(type: LoggingType) {
        self.isEnabled = true
        if type == .immediate {
            self.startLogger()
        }
    }

    func stop(ignoreEmptyLogs: Bool = false, customAlertMessage: ((String) -> String)? = nil) {
        self.isEnabled = false
        self.didStartFromLaunch = false

        guard let logger = self.logger else { return }

        DDLog.remove(logger)

        logger.rollLogFile { [weak self] in
            if self?.coordinator == nil {
                self?.pendingAction = PendingCoordinatorAction(ignoreEmptyLogs: ignoreEmptyLogs, customAlertMessage: customAlertMessage)
                return
            }

            self?.queue.async {
                self?.shareLogs(ignoreEmptyLogs: ignoreEmptyLogs, customAlertMessage: customAlertMessage)
                self?.logger = nil
            }
        }
    }

    func cancel() {
        self.isEnabled = false
        self.didStartFromLaunch = false

        guard let logger = self.logger else { return }

        DDLog.remove(logger)

        logger.rollLogFile { [weak self] in
            self?.queue.async {
                self?.clearDebugDirectory()
                self?.logger = nil
            }
        }
    }

    func startLoggingOnLaunchIfNeeded() {
        guard self.isEnabled else { return }
        self.didStartFromLaunch = true
        self.startLogger()
    }

    func storeLogs(completed: @escaping () -> Void) {
        guard let logger = self.logger else {
            completed()
            return
        }
        logger.rollLogFile(withCompletion: completed)
    }

    private func shareLogs(ignoreEmptyLogs: Bool, customAlertMessage: ((String) -> String)?) {
        DDLogInfo("DebugLogging: sharing logs")

        do {
            let logs: [URL] = try self.fileStorage.sortedContentsOfDirectory(at: Files.debugLogDirectory)

            if logs.isEmpty {
                if ignoreEmptyLogs {
                    self.clearDebugDirectory()
                    return
                }

                DDLogWarn("DebugLogging: no logs found")
                throw Error.noLogsRecorded
            }

            self.submit(logs: logs, customAlertMessage: customAlertMessage)
        } catch let error {
            DDLogError("DebugLogging: can't read debug directory contents - \(error)")
            inMainThread {
                self.coordinator?.show(error: (error as? Error) ?? .contentReading, logs: nil, retry: nil, completed: nil)
            }
        }
    }

    private func submit(logs: [URL], customAlertMessage: ((String) -> String)?) {
        guard let (completionAlert, progressAlert) = self.coordinator?.createDebugAlertActions() else { return }

        let data: Data
        do {
            data = try self.data(from: logs)
        } catch let error {
            DDLogError("DebugLogging: can't read all logs - \(error)")
            inMainThread {
                completionAlert(.failure((error as? Error) ?? .contentReading),
                                logs,
                                { [weak self] in // Retry block
                                    self?.submit(logs: logs, customAlertMessage: customAlertMessage)
                                },
                                { [weak self] in // Completion block
                                    self?.clearDebugDirectory()
                                })
            }
            return
        }

        let debugRequest = DebugLogUploadRequest()
        self.apiClient.upload(request: debugRequest, data: data, queue: self.queue)
                      .subscribe(on: self.scheduler)
                      .flatMap { data, _ -> Single<String> in
                          guard let data = data else { return Single.error(Error.responseParsing) }

                          let delegate = DebugResponseParserDelegate()
                          let parser = XMLParser(data: data)
                          parser.delegate = delegate

                          if parser.parse() {
                              return Single.just(delegate.reportId)
                          } else {
                              return Single.error(Error.responseParsing)
                          }
                      }
                      .observe(on: MainScheduler.instance)
                      .subscribe(onSuccess: { [weak self] debugId in
                          DDLogInfo("DebugLogging: uploaded logs")
                          self?.clearDebugDirectory()
                          let fullDebugId = "D" + debugId
                          completionAlert(.success((fullDebugId, customAlertMessage?(fullDebugId))), nil, nil, nil)
                      }, onFailure: { [weak self] error in
                          DDLogError("DebugLogging: can't upload logs - \(error)")
                          completionAlert(.failure((error as? Error) ?? .upload),
                                          logs,
                                          { // Retry block
                                              self?.submit(logs: logs, customAlertMessage: customAlertMessage)
                                          },
                                          { // Completion block
                                              self?.clearDebugDirectory()
                                          })
                      })
                      .disposed(by: self.disposeBag)
    }

    private func data(from logs: [URL]) throws -> Data {
        let timestamp = Date().timeIntervalSince1970
        var allLogs = DeviceInfoProvider.debugString + "\nTimestamp: \(timestamp)" + "\n\n"

        for url in logs {
            let string = try String(contentsOf: url)
            allLogs += string
        }

        guard let data = allLogs.data(using: .utf8) else {
            throw Error.cantCreateData
        }
        return data
    }

    private func clearDebugDirectory() {
        do {
            try self.fileStorage.remove(Files.debugLogDirectory)
        } catch let error {
            DDLogError("DebugLogging: can't delete directory - \(error)")
        }
    }

    private func startLogger() {
        guard self.logger == nil else { return }

        do {
            let file = Files.debugLogDirectory
            if self.fileStorage.has(file) {
                try self.fileStorage.remove(file)
            }
            try self.fileStorage.createDirectories(for: file)

            let manager = DDLogFileManagerDefault(logsDirectory: file.createUrl().path)
            let logger = DDFileLogger(logFileManager: manager)
            let targetName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? ""
            logger.logFormatter = DebugLogFormatter(targetName: targetName)
            logger.doNotReuseLogFiles = true
            logger.maximumFileSize = 100 * 1024 * 1024 // 100mb

            DDLog.add(logger)
            self.logger = logger
        } catch let error {
            DDLogError("DebugLogging: can't start logger - \(error)")
            self.coordinator?.show(error: .start, logs: nil, retry: nil, completed: nil)
        }
    }
}
