//
//  CrashReporter.swift
//  Zotero
//
//  Created by Michal Rentka on 18/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import CrashReporter
import RxSwift
import RxSwiftExt

protocol CrashReporterCoordinator: AnyObject {
    func report(id: String, completion: @escaping () -> Void)
}

final class CrashReporter {
    enum Error: Swift.Error {
        case responseParsing
    }

    private let reporter: PLCrashReporter
    private let apiClient: ApiClient
    private let disposeBag: DisposeBag
    private let queue: DispatchQueue
    private let scheduler: ConcurrentDispatchQueueScheduler

    weak var coordinator: CrashReporterCoordinator?

    init(apiClient: ApiClient) {
        let handler: PLCrashReporterSignalHandlerType
        #if DEBUG
        handler = .BSD
        #else
        handler = .mach
        #endif
        let config = PLCrashReporterConfig(signalHandlerType: handler, symbolicationStrategy: [])
        let queue = DispatchQueue(label: "org.zotero.CrashReporter", qos: .utility)

        self.reporter = PLCrashReporter(configuration: config)
        self.apiClient = apiClient
        self.queue = queue
        self.scheduler = ConcurrentDispatchQueueScheduler(queue: queue)
        self.disposeBag = DisposeBag()
    }

    func start() {
        self.queue.async {
            do {
                try self.reporter.enableAndReturnError()
            } catch let error {
                DDLogError("CrashReporter: can't start reporter - \(error)")
            }
        }
    }

    func processPendingReports(completion: @escaping () -> Void) {
        self.queue.async {
            guard self.reporter.hasPendingCrashReport() else {
                inMainThread {
                    completion()
                }
                return
            }
            self.handleCrashReport(completion: completion)
        }
    }

    private func handleCrashReport(completion: @escaping () -> Void) {
        do {
            let data = try self.reporter.loadPendingCrashReportDataAndReturnError()
            let report = try PLCrashReport(data: data)

            guard let text = PLCrashReportTextFormatter.stringValue(for: report, with: PLCrashReportTextFormatiOS) else {
                DDLogError("CrashReporter: can't convert report to text")
                self.cleanup()
                inMainThread {
                    completion()
                }
                return
            }

            let date = report.systemInfo.timestamp

            self.submit(crashLog: text).observe(on: MainScheduler.instance)
                                       .subscribe(onNext: { [weak self] reportId in
                                           self?.reportCrashIfNeeded(id: reportId, date: date, completion: completion)
                                           self?.cleanup()
                                        }, onError: { [weak self] error in
                                            DDLogError("CrashReporter: can't upload crash log - \(error)")
                                            self?.cleanup()
                                            completion()
                                        })
                                        .disposed(by: self.disposeBag)
        } catch let error {
            DDLogError("CrashReporter: can't load data - \(error)")
            self.cleanup()
            inMainThread {
                self.cleanup()
                completion()
            }
        }
    }

    private func submit(crashLog: String) -> Observable<String> {
        let request = CrashUploadRequest(crashLog: crashLog, deviceInfo: DeviceInfoProvider.crashString)
        return self.apiClient.send(request: request, queue: self.queue)
                             .mapData(httpMethod: request.httpMethod.rawValue)
                             .asObservable()
                             .observe(on: self.scheduler)
                             .flatMap { data, _ -> Observable<String> in
                                 let delegate = DebugResponseParserDelegate()
                                 let parser = XMLParser(data: data)
                                 parser.delegate = delegate

                                 if parser.parse() {
                                     return Observable.just(delegate.reportId)
                                 } else {
                                     return Observable.error(Error.responseParsing)
                                 }
                             }
    }

    private func reportCrashIfNeeded(id: String, date: Date?, completion: @escaping () -> Void) {
        guard let date = date else {
            self.coordinator?.report(id: id, completion: completion)
            return
        }
        // Don't report to user if crash happened more than 10 minutes ago
        guard Date().timeIntervalSince(date) <= 600 else {
            completion()
            return
        }
        self.coordinator?.report(id: id, completion: completion)
    }

    private func cleanup() {
        do {
            try self.reporter.purgePendingCrashReportAndReturnError()
        } catch let error {
            DDLogError("CrashReporter: can't purge data - \(error)")
        }
    }
}
