//
//  SyncProgressHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 01/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxCocoa
import RxSwift

typealias SyncProgressData = (Int, Int) // completed count, total count

enum SyncProgress {
    case groups
    case library(String, SyncObjectType, SyncProgressData?) // Library name, object, data
    case deletions(String) // Library name
    case finished([Error])
    case aborted(Error)
}

final class SyncProgressHandler {
    let observable: BehaviorRelay<SyncProgress?>
    private let finishVisibilityTime: Double = 2
    private let errorVisibilityTime: Double = 3.5

    private var libraryNames: [Int: String]?
    private var currentLibrary: String?
    private var currentDone: Int
    private var currentTotal: Int
    private var timerDisposeBag: DisposeBag

    init() {
        self.observable = BehaviorRelay(value: nil)
        self.currentDone = 0
        self.currentTotal = 0
        self.timerDisposeBag = DisposeBag()
    }

    // MARK: - Reporting

    func reportNewSync() {
        self.cleanup()
    }

    func reportGroupSync() {
        self.observable.accept(.groups)
    }

    func reportLibraryNames(data: [Int: String]) {
        self.libraryNames = data
    }

    func reportVersionsSync(for library: SyncLibraryType, object: SyncObjectType) {
        guard object != .group, let name = self.libraryNames?[library.libraryId] else { return }
        self.currentLibrary = name
        self.observable.accept(.library(name, object, nil))
    }

    func reportObjectCount(for object: SyncObjectType, count: Int) {
        self.currentTotal = count
        self.currentDone = 0
        self.reportCurrentNumbers(for: object)
    }

    func reportBatch(for object: SyncObjectType, count: Int) {
        self.currentDone += count
        self.reportCurrentNumbers(for: object)
    }

    func reportDeletions(for library: SyncLibraryType) {
        guard let name = self.libraryNames?[library.libraryId] else { return }
        self.observable.accept(.deletions(name))
    }

    func reportFinish(with errors: [Error]) {
        let timeout = errors.isEmpty ? self.finishVisibilityTime : self.errorVisibilityTime
        self.finish(with: .finished(errors), timeout: timeout)
    }

    func reportAbort(with error: Error) {
        self.finish(with: .aborted(error), timeout: self.errorVisibilityTime)
    }

    // MARK: - Helpers

    private func finish(with state: SyncProgress, timeout: Double) {
        self.cleanup()
        self.observable.accept(state)

        Single<Int>.timer(timeout, scheduler: MainScheduler.instance)
                   .subscribe(onSuccess: { [weak self] _ in
                       self?.observable.accept(nil)
                   })
                   .disposed(by: self.timerDisposeBag)
    }

    private func cleanup() {
        self.timerDisposeBag = DisposeBag()
        self.libraryNames = nil
        self.currentLibrary = nil
        self.currentDone = 0
        self.currentTotal = 0
    }

    private func reportCurrentNumbers(for object: SyncObjectType) {
        guard let name = self.currentLibrary, self.currentTotal > 0 else { return }
        self.observable.accept(.library(name, object, (self.currentDone, self.currentTotal)))
    }
}
