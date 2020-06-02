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

typealias SyncProgressData = (completed: Int, total: Int)

enum SyncProgress {
    case starting
    case groups(SyncProgressData?)
    case library(String)
    case object(object: SyncObject, progress: SyncProgressData?, library: String)
    case deletions(library: String)
    case changes(progress: SyncProgressData)
    case uploads(progress: SyncProgressData)
    case finished([Error])
    case aborted(Error)
}

final class SyncProgressHandler {
    let observable: BehaviorRelay<SyncProgress?>
    private let finishVisibilityTime: RxTimeInterval = .seconds(2)
    private let errorVisibilityTime: RxTimeInterval = .milliseconds(3500)

    private var libraryNames: [LibraryIdentifier: String]?
    private var currentDone: Int
    private var currentTotal: Int
    private var timerDisposeBag: DisposeBag

    private(set) var inProgress: Bool

    init() {
        self.observable = BehaviorRelay(value: nil)
        self.currentDone = 0
        self.currentTotal = 0
        self.inProgress = false
        self.timerDisposeBag = DisposeBag()
    }

    // MARK: - Reporting

    func set(libraryNames: [LibraryIdentifier: String]) {
        self.libraryNames = libraryNames
    }

    func reportNewSync() {
        self.cleanup()
        self.inProgress = true
        self.observable.accept(.starting)
    }

    func reportGroupsSync() {
        self.observable.accept(.groups(nil))
    }

    func reportGroupCount(count: Int) {
        self.currentTotal = count
        self.currentDone = 0
        self.reportGroupProgress()
    }

    func reportGroupSynced() {
        self.addDone(1)
        self.reportGroupProgress()
    }

    func reportLibrarySync(for libraryId: LibraryIdentifier) {
        guard let name = self.libraryNames?[libraryId] else { return }
        self.observable.accept(.library(name))
    }

    func reportObjectSync(for object: SyncObject, in libraryId: LibraryIdentifier) {
        guard let name = self.libraryNames?[libraryId] else { return }
        self.observable.accept(.object(object: object, progress: nil, library: name))
    }

    func reportDownloadCount(for object: SyncObject, count: Int, in libraryId: LibraryIdentifier) {
        self.currentTotal = count
        self.currentDone = 0
        self.reportDownloadObjectProgress(for: object, libraryId: libraryId)
    }

    func reportWrite(count: Int) {
        self.currentDone = 0
        self.currentTotal = count
        self.observable.accept(.changes(progress: (self.currentDone, self.currentTotal)))
    }

    func reportDownloadBatchSynced(size: Int, for object: SyncObject, in libraryId: LibraryIdentifier) {
        self.addDone(size)
        self.reportDownloadObjectProgress(for: object, libraryId: libraryId)
    }

    func reportWriteBatchSynced(size: Int) {
        self.addDone(size)
        self.observable.accept(.changes(progress: (self.currentDone, self.currentTotal)))
    }

    func reportUpload(count: Int) {
        self.currentTotal = count
        self.currentDone = 0
        self.observable.accept(.uploads(progress: (self.currentDone, self.currentTotal)))
    }

    func reportUploaded() {
        self.addDone(1)
        self.observable.accept(.uploads(progress: (self.currentDone, self.currentTotal)))
    }

    func reportDeletions(for libraryId: LibraryIdentifier) {
        guard let name = self.libraryNames?[libraryId] else { return }
        self.observable.accept(.deletions(library: name))
    }

    func reportFinish(with errors: [Error]) {
        let timeout = errors.isEmpty ? self.finishVisibilityTime : self.errorVisibilityTime
        self.finish(with: .finished(errors), timeout: timeout)
    }

    func reportAbort(with error: Error) {
        self.finish(with: .aborted(error), timeout: self.errorVisibilityTime)
    }

    // MARK: - Helpers

    private func addDone(_ done: Int) {
        self.currentDone = min((self.currentDone + done), self.currentTotal)
    }

    private func reportGroupProgress() {
        self.observable.accept(.groups((self.currentDone, self.currentTotal)))
    }

    private func reportDownloadObjectProgress(for object: SyncObject, libraryId: LibraryIdentifier) {
        guard let name =  self.libraryNames?[libraryId] else { return }
        self.observable.accept(.object(object: object, progress: (self.currentDone, self.currentTotal), library: name))
    }

    private func finish(with state: SyncProgress, timeout: RxTimeInterval) {
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
        self.inProgress = false
        self.currentDone = 0
        self.currentTotal = 0
    }
}
