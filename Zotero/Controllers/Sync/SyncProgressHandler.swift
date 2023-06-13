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
    case object(object: SyncObject, progress: SyncProgressData?, libraryName: String, libraryId: LibraryIdentifier)
    case deletions(library: String)
    case changes(progress: SyncProgressData)
    case uploads(progress: SyncProgressData)
    case finished([SyncError.NonFatal])
    case aborted(SyncError.Fatal)
}

final class SyncProgressHandler {
    let observable: PublishSubject<SyncProgress>

    private var libraryNames: [LibraryIdentifier: String]?
    private var currentDone: Int
    private var currentTotal: Int
    private var timerDisposeBag: DisposeBag

    private(set) var inProgress: Bool
    private(set) var libraryIdInProgress: LibraryIdentifier?

    init() {
        self.observable = PublishSubject()
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
        self.observable.on(.next(.starting))
    }

    func reportGroupsSync() {
        self.observable.on(.next(.groups(nil)))
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
        self.libraryIdInProgress = libraryId
        self.observable.on(.next(.library(name)))
    }

    func reportObjectSync(for object: SyncObject, in libraryId: LibraryIdentifier) {
        guard let name = self.libraryNames?[libraryId] else { return }
        self.observable.on(.next(.object(object: object, progress: nil, libraryName: name, libraryId: libraryId)))
    }

    func reportDownloadCount(for object: SyncObject, count: Int, in libraryId: LibraryIdentifier) {
        self.currentTotal = count
        self.currentDone = 0
        self.reportDownloadObjectProgress(for: object, libraryId: libraryId)
    }

    func reportWrite(count: Int) {
        self.currentDone = 0
        self.currentTotal = count
        self.observable.on(.next(.changes(progress: (self.currentDone, self.currentTotal))))
    }

    func reportDownloadBatchSynced(size: Int, for object: SyncObject, in libraryId: LibraryIdentifier) {
        self.addDone(size)
        self.reportDownloadObjectProgress(for: object, libraryId: libraryId)
    }

    func reportWriteBatchSynced(size: Int) {
        self.addDone(size)
        self.observable.on(.next(.changes(progress: (self.currentDone, self.currentTotal))))
    }

    func reportUpload(count: Int) {
        self.currentTotal = count
        self.currentDone = 0
        self.observable.on(.next(.uploads(progress: (self.currentDone, self.currentTotal))))
    }

    func reportUploaded() {
        self.addDone(1)
        self.observable.on(.next(.uploads(progress: (self.currentDone, self.currentTotal))))
    }

    func reportDeletions(for libraryId: LibraryIdentifier) {
        guard let name = self.libraryNames?[libraryId] else { return }
        self.observable.on(.next(.deletions(library: name)))
    }

    func reportFinish(with errors: [SyncError.NonFatal]) {
        self.finish(with: .finished(errors))
    }

    func reportAbort(with error: SyncError.Fatal) {
        self.finish(with: .aborted(error))
    }

    // MARK: - Helpers

    private func addDone(_ done: Int) {
        self.currentDone = min((self.currentDone + done), self.currentTotal)
    }

    private func reportGroupProgress() {
        self.observable.on(.next(.groups((self.currentDone, self.currentTotal))))
    }

    private func reportDownloadObjectProgress(for object: SyncObject, libraryId: LibraryIdentifier) {
        guard let name = self.libraryNames?[libraryId] else { return }
        self.observable.on(.next(.object(object: object, progress: (self.currentDone, self.currentTotal), libraryName: name, libraryId: libraryId)))
    }

    private func finish(with state: SyncProgress) {
        self.cleanup()
        self.observable.on(.next(state))
    }

    private func cleanup() {
        self.timerDisposeBag = DisposeBag()
        self.libraryNames = nil
        self.inProgress = false
        self.currentDone = 0
        self.currentTotal = 0
        self.libraryIdInProgress = nil
    }
}
