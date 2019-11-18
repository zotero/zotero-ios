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

class CrashReporter {
    private let reporter: PLCrashReporter
    private let apiClient: ApiClient
    private let queue: DispatchQueue
    private let scheduler: ConcurrentDispatchQueueScheduler
    private let disposeBag: DisposeBag

    init(apiClient: ApiClient) {
        self.reporter = PLCrashReporter.shared()
        self.apiClient = apiClient
        let queue = DispatchQueue.global(qos: .utility)
        self.queue = queue
        self.scheduler = ConcurrentDispatchQueueScheduler(queue: queue)
        self.disposeBag = DisposeBag()
    }

    func start() {
        self.queue.async { [weak self] in
            do {
                try self?.reporter.enableAndReturnError()
            } catch let error {
                DDLogError("CrashReporter: can't start reporter - \(error)")
            }
        }
    }

    func processPendingReports() {
        self.queue.async { [weak self] in
            guard let `self` = self, self.reporter.hasPendingCrashReport() else { return }
            self.handleCrashReport()
        }
    }

    private func handleCrashReport() {
        do {
            let data = try self.reporter.loadPendingCrashReportDataAndReturnError()

            let repeatBehavior: RepeatBehavior = .exponentialDelayed(maxCount: 10, initial: 5, multiplier: 1.5)
            self.upload(data: data).retry(repeatBehavior, scheduler: self.scheduler)
                                   .subscribe(onError: { error in
                                       DDLogError("CrashReporter: can't upload crash log - \(error)")
                                   }, onCompleted: { [weak self] in
                                       self?.cleanup()
                                   })
                                   .disposed(by: self.disposeBag)
        } catch let error {
            DDLogError("CrashReporter: can't load data - \(error)")
        }
    }

    private func upload(data: Data) -> Observable<()> {
        return Observable.just(())
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
    }

    private func cleanup() {
        do {
            try self.reporter.purgePendingCrashReportAndReturnError()
        } catch let error {
            DDLogError("CrashReporter: can't purge data - \(error)")
        }
    }
}
