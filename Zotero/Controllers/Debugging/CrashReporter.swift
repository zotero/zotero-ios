//
//  CrashReporter.swift
//  Zotero
//
//  Created by Michal Rentka on 18/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack
import RxSwift
import RxSwiftExt

protocol CrashReporterCoordinator: class {
    func report(crash: String, completed: @escaping () -> Void)
}

class CrashReporter {
    private let reporter: PLCrashReporter
    private let apiClient: ApiClient
    private let disposeBag: DisposeBag

    private var pendingReport: String?
    weak var coordinator: CrashReporterCoordinator? {
        didSet {
            if let crash = self.pendingReport, let coordinator = self.coordinator {
                self.report(crash: crash, in: coordinator)
            }
        }
    }

    init(apiClient: ApiClient) {
        let config = PLCrashReporterConfig(signalHandlerType: .BSD, symbolicationStrategy: .all)
        self.reporter = PLCrashReporter(configuration: config)
        self.apiClient = apiClient
        self.disposeBag = DisposeBag()
    }

    func start() {
        do {
            try self.reporter.enableAndReturnError()
        } catch let error {
            DDLogError("CrashReporter: can't start reporter - \(error)")
        }
    }

    func processPendingReports() {
        guard self.reporter.hasPendingCrashReport() else { return }
        self.handleCrashReport()
    }

    private func handleCrashReport() {
        do {
            let data = try self.reporter.loadPendingCrashReportDataAndReturnError()
            let report = try PLCrashReport(data: data)
            if let text = PLCrashReportTextFormatter.stringValue(for: report, with: PLCrashReportTextFormatiOS) {
                if let coordinator = self.coordinator {
                    self.report(crash: text, in: coordinator)
                } else {
                    self.pendingReport = text
                }
            }
//            let repeatBehavior: RepeatBehavior = .exponentialDelayed(maxCount: 10, initial: 5, multiplier: 1.5)
//            self.upload(data: data).retry(repeatBehavior, scheduler: self.scheduler)
//                                   .subscribe(onError: { error in
//                                       DDLogError("CrashReporter: can't upload crash log - \(error)")
//                                   }, onCompleted: { [weak self] in
//                                       self?.cleanup()
//                                   })
//                                   .disposed(by: self.disposeBag)
        } catch let error {
            DDLogError("CrashReporter: can't load data - \(error)")
        }
    }

    private func report(crash: String, in coordinator: CrashReporterCoordinator) {
        coordinator.report(crash: crash) { [weak self] in
            self?.cleanup()
        }
    }

//    private func upload(data: Data) -> Observable<()> {
//        return Observable.just(())
        // TODO: - Add actual API request when availble
        /*
        let request = CrashUploadRequest()
        return self.apiClient.upload(request: request) { $0.append(data, withName: "crashlog") }
                             .asObservable()
                             .observeOn(self.scheduler)
                             .flatMap { request in
                                 return request.rx.data()
                             }
                             .flatMap { _ in
                                return Observable.just(())
                             }
         */
//    }

    private func cleanup() {
        do {
            try self.reporter.purgePendingCrashReportAndReturnError()
        } catch let error {
            DDLogError("CrashReporter: can't purge data - \(error)")
        }
    }
}
