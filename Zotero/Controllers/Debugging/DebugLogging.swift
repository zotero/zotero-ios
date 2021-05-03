//
//  DebugLogging.swift
//  Zotero
//
//  Created by Michal Rentka on 04/03/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxAlamofire
import RxSwift

protocol DebugLoggingCoordinator: AnyObject {
    func createDebugAlertActions() -> ((Result<String, DebugLogging.Error>, [URL]?, (() -> Void)?, (() -> Void)?) -> Void, (Double) -> Void)
    func show(error: DebugLogging.Error, logs: [URL]?, retry: (() -> Void)?, completed: (() -> Void)?)
    func setDebugWindow(visible: Bool)
}

final class DebugLogging {
    enum LoggingType {
        case immediate, nextLaunch
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
    private var logger: DDFileLogger?
    weak var coordinator: DebugLoggingCoordinator?

    init(apiClient: ApiClient, fileStorage: FileStorage) {
        let queue = DispatchQueue(label: "org.zotero.DebugLogging.Queue", qos: .userInitiated)
        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.queue = queue
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

    func stop() {
        self.isEnabled = false

        guard let logger = self.logger else { return }

        DDLog.remove(logger)

        logger.rollLogFile { [weak self] in
            self?.queue.async {
                self?.shareLogs()
                self?.logger = nil
            }
        }
    }

    func startLoggingOnLaunchIfNeeded() {
        guard self.isEnabled else { return }
        self.startLogger()
    }

    func storeLogs(completed: @escaping () -> Void) {
        guard let logger = self.logger else {
            completed()
            return
        }
        logger.rollLogFile(withCompletion: completed)
    }

    private func shareLogs() {
        DDLogInfo("DebugLogging: sharing logs")

        do {
            let logs: [URL] = try self.fileStorage.sortedContentsOfDirectory(at: Files.debugLogDirectory)
            if logs.isEmpty {
                DDLogWarn("DebugLogging: no logs found")
                throw Error.noLogsRecorded
            }
            self.submit(logs: logs)
        } catch let error {
            DDLogError("DebugLogging: can't read debug directory contents - \(error)")
            inMainThread {
                self.coordinator?.show(error: (error as? Error) ?? .contentReading, logs: nil, retry: nil, completed: nil)
            }
        }
    }

    private func submit(logs: [URL]) {
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
                                    self?.submit(logs: logs)
                                },
                                { [weak self] in // Completion block
                                    self?.clearDebugDirectory()
                                })
            }
            return
        }

        let debugRequest = DebugLogUploadRequest()
        let startTime = CFAbsoluteTimeGetCurrent()
        self.apiClient.upload(request: debugRequest, data: data)
                      .subscribeOn(self.scheduler)
                      .flatMap { request -> Single<(HTTPURLResponse, Data)> in
                          let logId = ApiLogger.log(request: debugRequest, url: request.request?.url)
                          request.uploadProgress { progress in
                              DDLogInfo("DebugLogging: progress \(progress.fractionCompleted)")
                              progressAlert(progress.fractionCompleted)
                          }
                          return request.rx.responseData().subscribeOn(self.scheduler).log(identifier: logId, startTime: startTime, request: debugRequest).asSingle()
                      }
                      .flatMap { _, data -> Single<String> in
                          let delegate = DebugResponseParserDelegate()
                          let parser = XMLParser(data: data)
                          parser.delegate = delegate

                          if parser.parse() {
                              return Single.just(delegate.reportId)
                          } else {
                              return Single.error(Error.responseParsing)
                          }
                      }
                      .observeOn(MainScheduler.instance)
                      .subscribe(onSuccess: { [weak self] debugId in
                          DDLogInfo("DebugLogging: uploaded logs")
                          self?.clearDebugDirectory()
                          completionAlert(.success("D" + debugId), nil, nil, nil)
                      }, onError: { [weak self] error in
                          DDLogError("DebugLogging: can't upload logs - \(error)")
                          completionAlert(.failure((error as? Error) ?? .upload),
                                          logs,
                                          { // Retry block
                                              self?.submit(logs: logs)
                                          },
                                          { // Completion block
                                              self?.clearDebugDirectory()
                                          })
                      })
                      .disposed(by: self.disposeBag)
    }

    private func data(from logs: [URL]) throws -> Data {
        var allLogs = DeviceInfoProvider.debugString + "\n\n"

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
