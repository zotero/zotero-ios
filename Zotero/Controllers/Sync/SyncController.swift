//
//  SyncController.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import CocoaLumberjack
import RealmSwift
import RxSwift

enum SyncError: Error {
    case cancelled
    // Abort (fatal) errors
    case noInternetConnection
    case apiError
    case dbError
    case versionMismatch
    case groupSyncFailed(Error)
    case allLibrariesFetchFailed(Error)
}

extension SyncError: Equatable {
    static func ==(lhs: SyncError, rhs: SyncError) -> Bool {
        switch (lhs, rhs) {
        case (.noInternetConnection, .noInternetConnection),
             (.apiError, .apiError),
             (.dbError, .dbError),
             (.versionMismatch, .versionMismatch),
             (.groupSyncFailed, .groupSyncFailed),
             (.allLibrariesFetchFailed, .allLibrariesFetchFailed):
            return true
        default:
            return false
        }
    }
}

struct ObjectBatch {
    static var maxObjectCount = 50

    let order: Int
    let library: SyncLibraryType
    let object: SyncObjectType
    let keys: [Any]
    let version: Int

    var keysString: String {
        return self.keys.map({ "\($0)" }).joined(separator: ",")
    }
}

enum QueueAction: Equatable {
    case syncVersions(SyncLibraryType, SyncObjectType, Int?)     // Fetch versions from API, update DB based on response
    case syncBatchToFile(ObjectBatch)                            // Fetch data for new/updated objects, store to files
    case createLibraryActions                                    // Load all libraries, spawn actions for each
    case syncBatchToDb(ObjectBatch)                              // Stores file data to db
    case storeVersion(Int, SyncLibraryType, SyncObjectType)      // Store new version for given library-object
    case syncDeletions(SyncLibraryType, Int)                     // Synchronize deletions of objects in library
    case syncSettings(SyncLibraryType, Int)                      // Synchronize settings for library

    var library: SyncLibraryType? {
        switch self {
        case .createLibraryActions:
            return nil
        case .syncBatchToFile(let action),
             .syncBatchToDb(let action):
            return action.library
        case .syncVersions(let library, _, _),
             .storeVersion(_, let library, _),
             .syncDeletions(let library, _),
             .syncSettings(let library, _):
            return library
        }
    }
}

extension ObjectBatch: Equatable {
    public static func ==(lhs: ObjectBatch, rhs: ObjectBatch) -> Bool {
        if lhs.keys.count != rhs.keys.count {
            return false
        }
        for i in 0..<lhs.keys.count {
            if let lInt = lhs.keys[i] as? Int, let rInt = rhs.keys[i] as? Int {
                if lInt != rInt {
                    return false
                }
            } else if let lStr = lhs.keys[i] as? String, let rStr = rhs.keys[i] as? String {
                if lStr != rStr {
                    return false
                }
            } else {
                return false
            }
        }
        return lhs.order == rhs.order && lhs.library == rhs.library &&
               lhs.object == rhs.object && lhs.version == rhs.version
    }
}

final class SyncController {
    private static let timeoutPeriod: Double = 15.0

    private let userId: Int
    private let accessQueue: DispatchQueue
    private let handler: SyncActionHandler

    private var queue: [QueueAction]
    private var processingAction: QueueAction?
    private var nonFatalErrors: [Error]
    private var needsResync: Bool
    private var isResyncing: Bool
    private var lastReturnedVersion: Int?
    private var isInitial: Bool
    private var disposeBag: DisposeBag

    private var isSyncing: Bool {
        return self.processingAction != nil || !self.queue.isEmpty || self.needsResync
    }

    init(userId: Int, handler: SyncActionHandler) {
        self.userId = userId
        self.accessQueue = DispatchQueue(label: "org.zotero.SyncAccessQueue", qos: .utility, attributes: .concurrent)
        self.handler = handler
        self.disposeBag = DisposeBag()
        self.queue = []
        self.nonFatalErrors = []
        self.needsResync = false
        self.isResyncing = false
        self.isInitial = false
    }

    // MARK: - Sync management

    func start(isInitial: Bool = false) {
        DDLogInfo("--- Sync: starting ---")
        self.start(isResync: false, isInitial: isInitial)
    }

    func cancelSync() {
        DDLogInfo("--- Sync: cancelled ---")

        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            guard let `self` = self, self.isSyncing else { return }
            self.disposeBag = DisposeBag()
            self.cleaup()
        }

        inMainThread {
            self.report(fatalError: SyncError.cancelled)
        }
    }

    private func start(isResync: Bool, isInitial: Bool) {
        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            guard let `self` = self, !self.isSyncing else { return }
            if isResync {
                self.needsResync = false
                self.isResyncing = true
            }
            self.isInitial = isInitial
            self.queue.append(.syncVersions(.user(self.userId), .group, nil))
            self.processNextAction()
        }
    }

    private func finish() {
        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            guard let `self` = self else { return }

            let errors = self.nonFatalErrors

            DDLogInfo("--- Sync: finished ---")
            if !errors.isEmpty {
                DDLogInfo("Errors: \(errors)")
            }

            self.reportFinish?(.success((self.allActions, errors)))
            self.reportFinish = nil

            if !errors.isEmpty {
                inMainThread {
                    self.report(nonFatalErrors: errors)
                }
            }

            self.enqueueResyncIfNeeded()
            self.cleaup()
        }
    }

    private func abort(error: Error) {
        inMainThread {
            self.report(fatalError: error)
        }

        DDLogInfo("--- Sync: aborted ---")
        DDLogInfo("Error: \(error)")

        self.reportFinish?(.failure(error))
        self.reportFinish = nil

        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            guard let `self` = self else { return }
            self.cleaup()
            self.needsResync = true
            self.enqueueResync()
        }
    }

    private func enqueueResyncIfNeeded() {
        guard self.needsResync else { return }
        self.enqueueResync()
    }

    private func enqueueResync() {
        Single<Int>.timer(SyncController.timeoutPeriod, scheduler: MainScheduler.instance)
                   .subscribe(onSuccess: { [weak self] _ in
                       self?.start(isResync: true, isInitial: false)
                   })
                   .disposed(by: self.disposeBag)
    }

    private func setNeedsResync() {
        guard !self.isResyncing else { return }
        self.needsResync = true
    }

    private func cleaup() {
        self.processingAction = nil
        self.queue = []
        self.nonFatalErrors = []
        self.needsResync = false
        self.isResyncing = false
        self.lastReturnedVersion = nil
        self.isInitial = false
    }

    // MARK: - Error handling

    private func report(fatalError: Error) {
        // TODO: - Show some error to the user mentioning the whole sync stopped and will restart in a while
    }

    private func report(nonFatalErrors errors: [Error]) {
        // TODO: - Show some error to user mentioning all errors?
    }

    // MARK: - Queue management

    private func enqueue(actions: [QueueAction], at index: Int? = nil) {
        if let index = index {
            self.queue.insert(contentsOf: actions, at: index)
        } else {
            self.queue.append(contentsOf: actions)
        }
        self.processNextAction()
    }

    private func removeAllActions(for library: SyncLibraryType) {
        while !self.queue.isEmpty {
            guard self.queue[0].library == library else { break }
            self.queue.removeFirst()
        }
    }

    private func processNextAction() {
        guard !self.queue.isEmpty else {
            self.processingAction = nil
            self.finish()
            return
        }

        let action = self.queue.removeFirst()

        if self.reportFinish != nil {
            self.allActions.append(action)
        }

        // Library is changing, reset "lastReturnedVersion"
        if self.lastReturnedVersion != nil && action.library != self.processingAction?.library {
            self.lastReturnedVersion = nil
        }

        self.processingAction = action
        self.process(action: action)
    }

    // MARK: - Action processing

    private func process(action: QueueAction) {
        DDLogInfo("--- Sync: action ---")
        DDLogInfo("\(action)")
        switch action {
        case .createLibraryActions:
            self.processAllLibrariesSync()
        case .syncVersions(let library, let objectType, let version):
            self.processSyncVersionsAction(library: library, object: objectType, since: version)
        case .syncBatchToFile(let batch):
            self.processFileStoreAction(for: batch)
        case .syncBatchToDb(let batch):
            self.processDbStoreAction(for: batch)
        case .storeVersion(let version, let library, let object):
            self.processStoreVersionAction(library: library, object: object, version: version)
        case .syncDeletions(let library, let version):
            self.processDeletionsSync(library: library, since: version)
        case .syncSettings(let library, let version):
            self.processSettingsSync(for: library, version: version)
        }
    }

    private func processAllLibrariesSync() {
        let userId = self.userId
        self.handler.loadAllLibraryIdsAndVersions()
                    .flatMap { libraryData in
                        var versionedLibraries: [(SyncLibraryType, Versions)] = []
                        for data in libraryData {
                            if data.0 == RLibrary.myLibraryId {
                                versionedLibraries.append((.user(userId), data.1))
                            } else {
                                versionedLibraries.append((.group(data.0), data.1))
                            }
                        }
                        return Single.just(versionedLibraries)
                    }
                    .subscribe(onSuccess: { [weak self] libraries in
                        self?.finishAllLibrariesSync(with: .success(libraries))
                    }, onError: { [weak self] error in
                        self?.finishAllLibrariesSync(with: .failure(error))
                    })
                    .disposed(by: self.disposeBag)
    }

    private func finishAllLibrariesSync(with result: Result<[(SyncLibraryType, Versions)]>) {
        switch result {
        case .failure(let error):
            self.abort(error: SyncError.allLibrariesFetchFailed(error))

        case .success(let libraryData):
            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                guard let `self` = self else { return }

                var allActions: [QueueAction] = []
                libraryData.forEach { data in
                    let actions: [QueueAction] = [.syncSettings(data.0, data.1.settings),
                                                  .syncVersions(data.0, .collection, data.1.collections),
                                                  .syncVersions(data.0, .item, data.1.items),
                                                  .syncVersions(data.0, .trash, data.1.trash),
                                                  .syncVersions(data.0, .search, data.1.searches),
                                                  .syncDeletions(data.0, data.1.deletions)]
                    allActions.append(contentsOf: actions)
                }
                self.enqueue(actions: allActions)
            }
        }
    }

    private func processSyncVersionsAction(library: SyncLibraryType, object: SyncObjectType, since version: Int?) {
        self.handler.synchronizeVersions(for: library, object: object, since: version,
                                         current: self.lastReturnedVersion, syncAll: self.isInitial)
                    .subscribe(onSuccess: { [weak self] data in
                        self?.finishSyncVersionsAction(for: library, object: object, result: .success((data.1, data.0)))
                    }, onError: { [weak self] error in
                        self?.finishSyncVersionsAction(for: library, object: object, result: .failure(error))
                    })
                    .disposed(by: self.disposeBag)
    }

    private func finishSyncVersionsAction(for library: SyncLibraryType, object: SyncObjectType,
                                          result: Result<([Any], Int)>) {
        switch result {
        case .success(let data):
            self.createBatchedActions(from: data.0, currentVersion: data.1, library: library, object: object)

        case .failure(let error):
            if let abortError = self.errorRequiresAbort(error, library: library, object: object) {
                self.abort(error: abortError)
                return
            }

            if object == .group {
                self.abort(error: SyncError.groupSyncFailed(error))
                return
            }

            if self.handleVersionMismatchIfNeeded(for: error, library: library) { return }

            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                guard let `self` = self else { return }
                self.nonFatalErrors.append(error)
                self.processNextAction()
            }
        }
    }

    private func createBatchedActions(from keys: [Any], currentVersion: Int,
                                      library: SyncLibraryType, object: SyncObjectType) {
        let batches: [ObjectBatch]
        switch object {
        case .group:
            batches = keys.enumerated().map { ObjectBatch(order: $0.offset, library: library, object: object,
                                                          keys: [$0.element], version: currentVersion) }
        default:
            batches = self.createBatchObjects(for: keys, library: library, object: object, version: currentVersion)
        }

        var actions: [QueueAction] = []
        batches.forEach { batch in
            actions.append(.syncBatchToFile(batch))
            actions.append(.syncBatchToDb(batch))
        }
        if object == .group {
            actions.append(.createLibraryActions)
        } else {
            actions.append(.storeVersion(currentVersion, library, object))
        }

        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            if object != .group {
                self?.lastReturnedVersion = currentVersion
            }
            self?.enqueue(actions: actions, at: 0)
        }
    }

    private func createBatchObjects(for keys: [Any], library: SyncLibraryType,
                                    object: SyncObjectType, version: Int) -> [ObjectBatch] {
        let maxBatchSize = ObjectBatch.maxObjectCount
        var batchSize = 5
        var processed = 0
        var batches: [ObjectBatch] = []

        while processed < keys.count {
            let upperBound = min((keys.count - processed), batchSize) + processed
            let batchKeys = Array(keys[processed..<upperBound])

            batches.append(ObjectBatch(order: batches.count, library: library, object: object,
                                       keys: batchKeys, version: version))

            processed += batchSize
            if batchSize < maxBatchSize {
                batchSize = min(batchSize * 2, maxBatchSize)
            }
        }

        return batches
    }

    private func processFileStoreAction(for batch: ObjectBatch) {
        self.handler.downloadObjectJson(for: batch.keysString, library: batch.library,
                                        object: batch.object, version: batch.version, index: batch.order)
                    .subscribe(onCompleted: { [weak self] in
                        self?.finishFileStoreAction(for: batch, error: nil)
                    }, onError: { [weak self] error in
                        self?.finishFileStoreAction(for: batch, error: error)
                    })
                    .disposed(by: self.disposeBag)
    }

    private func finishFileStoreAction(for batch: ObjectBatch, error: Error?) {
        guard let error = error else {
            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                self?.processNextAction()
            }
            return
        }

        if let abortError = self.errorRequiresAbort(error, library: batch.library, object: batch.object) {
            self.abort(error: abortError)
            return
        }

        if self.handleVersionMismatchIfNeeded(for: error, library: batch.library) { return }

        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            self?.nonFatalErrors.append(error)
        }

        // We couldn't fetch batch of up to ObjectAction.maxObjectCount objects, some objects will probably be
        // missing parents or completely, but we continue with the sync
        // We mark these objects as missing and we'll try to fetch and update them on next sync
        self.markForResync(keys: batch.keys, library: batch.library, object: batch.object)
    }

    private func processDbStoreAction(for batch: ObjectBatch) {
        self.handler.synchronizeDbWithFetchedFiles(library: batch.library, object: batch.object,
                                                   version: batch.version, index: batch.order)
                    .subscribe(onSuccess: { [weak self] decodingData in
                        self?.finishDbStoreAction(for: batch.library, object: batch.object,
                                                  allKeys: batch.keys, result: .success(decodingData))
                    }, onError: { [weak self] error in
                        self?.finishDbStoreAction(for: batch.library, object: batch.object,
                                                  allKeys: batch.keys, result: .failure(error))
                    })
                    .disposed(by: self.disposeBag)
    }

    private func finishDbStoreAction(for library: SyncLibraryType, object: SyncObjectType, allKeys: [Any],
                                     result: Result<([String], [Error])>) {
        switch result {
        case .success(let decodingData):
            if object == .group {
                // Groups always sync 1-by-1, so if an error happens it's always reported as .failure, only successful
                // actions are reported here, so we can directly skip to next action
                self.performOnAccessQueue(flags: .barrier) { [weak self] in
                    self?.processNextAction()
                }
                return
            }

            // Decoding of other objects is performed in batches, out of the whole batch only some objects may fail,
            // so these failures are reported as success (because some succeeded) and failed ones are marked for resync

            if !decodingData.1.isEmpty {
                self.performOnAccessQueue(flags: .barrier) { [weak self] in
                    self?.nonFatalErrors.append(contentsOf: decodingData.1)
                }
            }

            let allStringKeys = (allKeys as? [String]) ?? []
            let failedKeys = allStringKeys.filter({ !decodingData.0.contains($0) })

            if failedKeys.isEmpty {
                self.performOnAccessQueue(flags: .barrier) { [weak self] in
                    self?.processNextAction()
                }
                return
            }

            self.markForResync(keys: Array(failedKeys), library: library, object: object)
        case .failure(let error):
            if let abortError = self.errorRequiresAbort(error) {
                self.abort(error: abortError)
                return
            }

            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                self?.nonFatalErrors.append(error)
            }

            // We failed to sync the whole batch, mark all for resync and continue with sync
            self.markForResync(keys: allKeys, library: library, object: object)
        }
    }

    private func processStoreVersionAction(library: SyncLibraryType, object: SyncObjectType, version: Int) {
        self.handler.storeVersion(version, for: library, object: object)
                    .subscribe(onCompleted: { [weak self] in
                        self?.finishProcessingStoreVersionAction(error:  nil)
                    }, onError: { [weak self] error in
                        self?.finishProcessingStoreVersionAction(error: error)
                    })
                    .disposed(by: self.disposeBag)
    }

    private func finishProcessingStoreVersionAction(error: Error?) {
        guard let error = error else {
            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                self?.processNextAction()
            }
            return
        }

        if let abortError = self.errorRequiresAbort(error) {
            self.abort(error: abortError)
            return
        }

        // If we only failed to store correct versions we can continue as usual, we'll just try to fetch from
        // older version on next sync and most objects will be up to date
        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            self?.nonFatalErrors.append(error)
            self?.processNextAction()
        }
    }

    private func markForResync(keys: [Any], library: SyncLibraryType, object: SyncObjectType) {
        self.handler.markForResync(keys: keys, library: library, object: object)
                    .subscribe(onCompleted: { [weak self] in
                        self?.performOnAccessQueue(flags: .barrier) { [weak self] in
                            guard let `self` = self else { return }
                            self.setNeedsResync()
                            self.processNextAction()
                        }
                    }, onError: { [weak self] error in
                        self?.performOnAccessQueue(flags: .barrier) { [weak self] in
                            guard let `self` = self else { return }
                            self.nonFatalErrors.append(error)
                            self.removeAllActions(for: library)
                            self.processNextAction()
                        }
                    })
                    .disposed(by: self.disposeBag)
    }

    private func processDeletionsSync(library: SyncLibraryType, since sinceVersion: Int) {
        self.handler.synchronizeDeletions(for: library, since: sinceVersion, current: self.lastReturnedVersion)
                    .subscribe(onCompleted: { [weak self] in
                        self?.finishDeletionsSync(error: nil)
                    }, onError: { [weak self] error in
                        self?.finishDeletionsSync(error: error)
                    })
                    .disposed(by: self.disposeBag)
    }

    private func finishDeletionsSync(error: Error?) {
        guard let error = error else {
            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                self?.processNextAction()
            }
            return
        }

        if let abortError = self.errorRequiresAbort(error) {
            self.abort(error: abortError)
            return
        }

        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            self?.nonFatalErrors.append(error)
            self?.processNextAction()
        }
    }

    private func processSettingsSync(for library: SyncLibraryType, version: Int) {
        self.handler.synchronizeSettings(for: library, since: version)
                    .subscribe(onCompleted: { [weak self] in
                        self?.performOnAccessQueue(flags: .barrier) { [weak self] in
                            self?.processNextAction()
                        }
                    }, onError: { [weak self] error in
                        self?.performOnAccessQueue(flags: .barrier) { [weak self] in
                            self?.nonFatalErrors.append(error)
                            self?.processNextAction()
                        }
                    })
                    .disposed(by: self.disposeBag)
    }

    // MARK: - Helpers

    private func performOnAccessQueue(flags: DispatchWorkItemFlags = [], action: @escaping () -> Void) {
        self.accessQueue.async(flags: flags) {
            action()
        }
    }

    private func errorRequiresAbort(_ error: Error, library: SyncLibraryType? = nil,
                                    object: SyncObjectType? = nil) -> Error? {
        let nsError = error as NSError

        // Check connection
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorNotConnectedToInternet {
            return SyncError.noInternetConnection
        }

        // Check other networking errors
        if let alamoError = error as? AFError {
            switch alamoError {
            case .responseValidationFailed(let reason):
                switch reason {
                case .unacceptableStatusCode(let code):
                    return (code >= 400 && code < 500) ? SyncError.apiError : nil
                case .dataFileNil, .dataFileReadFailed, .missingContentType, .unacceptableContentType:
                    return SyncError.apiError
                }
            case .multipartEncodingFailed, .parameterEncodingFailed, .invalidURL:
                return SyncError.apiError
            case .responseSerializationFailed:
                return nil
            }
        }

        // Check realm errors, every "core" error is bad. Can't create new Realm instance, can't continue with sync
        if error is Realm.Error {
            return SyncError.dbError
        }

        return nil
    }

    private func handleVersionMismatchIfNeeded(for error: Error, library: SyncLibraryType) -> Bool {
        guard error.isMismatchError else { return false }

        // If the backend received higher version in response than from previous responses,
        // there was a change on backend and we'll probably have conflicts, abort this library
        // and continue with sync
        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            guard let `self` = self else { return }
            self.nonFatalErrors.append(error)
            self.removeAllActions(for: library)
            self.processNextAction()
        }
        return true
    }

    // MARK: - Testing

    private var reportFinish: ((Result<([QueueAction], [Error])>) -> Void)?
    private var allActions: [QueueAction] = []

    func start(with queue: [QueueAction], finishedAction: @escaping (Result<([QueueAction], [Error])>) -> Void) {
        self.queue = queue
        self.allActions = []
        self.reportFinish = finishedAction
        self.processNextAction()
    }
}

extension Error {
    var isMismatchError: Bool {
        return (self as? SyncActionHandlerError) == .versionMismatch
    }
}
