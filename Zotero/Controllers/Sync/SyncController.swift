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
import RxCocoa
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
    case uploadObjectConflict
}

protocol SynchronizationController: class {
    var isSyncing: Bool { get }
    var observable: PublishSubject<(SyncController.SyncType, SyncController.LibrarySyncType)?> { get }
    var progressObservable: BehaviorRelay<SyncProgress?> { get }

    func start(type: SyncController.SyncType, libraries: SyncController.LibrarySyncType)
    func cancel()
}

final class SyncController: SynchronizationController {
    enum SyncType {
        case normal                 // Only objects which need to be synced are fetched. Either synced objects
                                    // with old version or unsynced objects with backoff schedule.
        case ignoreIndividualDelays // Same as .normal, but individual backoff schedule is ignored.
        case all                    // All objects are fetched. Both individual backoff schedule and local versions are ignored.
        case retry                  // A retry after previous broken sync.
    }

    enum LibrarySyncType: Equatable {
        case all                              // Syncs all libraries
        case specific([LibraryIdentifier])    // Syncs only specific libraries
    }

    enum Library: Equatable {
        case user(Int, RCustomLibraryType)
        case group(Int)
    }

    enum Object: Equatable, CaseIterable {
        case group, collection, search, item, trash, tag
    }

    struct DownloadBatch {
        static let maxCount = 50
        let library: Library
        let object: Object
        let keys: [Any]
        let version: Int
    }

    struct WriteBatch {
        static let maxCount = 50
        let library: Library
        let object: Object
        let version: Int
        let parameters: [[String: Any]]

        func copy(withVersion version: Int) -> WriteBatch {
            return WriteBatch(library: self.library, object: self.object, version: version, parameters: self.parameters)
        }
    }

    struct DeleteBatch {
        static let maxCount = 50
        let library: Library
        let object: Object
        let version: Int
        let keys: [String]

        func copy(withVersion version: Int) -> DeleteBatch {
            return DeleteBatch(library: self.library, object: self.object, version: version, keys: self.keys)
        }
    }

    enum Action: Equatable {
        case syncVersions(Library, Object, Int?)               // Fetch versions from API, update DB based on response
        case createLibraryActions(LibrarySyncType,
                                  CreateLibraryActionsOptions) // Loads required libraries, spawn actions for each
        case syncBatchToDb(DownloadBatch)                      // Fetch data and store to db
        case storeVersion(Int, Library, Object)                // Store new version for given library-object
        case syncDeletions(Library, Int)                       // Synchronize deletions of objects in library
        case syncSettings(Library, Int?)                       // Synchronize settings for library
        case storeSettingsVersion(Int, Library)                // Store new version for settings in library
        case submitWriteBatch(WriteBatch)                      // Submit local changes to backend
        case submitDeleteBatch(DeleteBatch)                    // Submit local deletions to backend
        case resolveConflict(String, Library)                  // Handle conflict resolution
    }

    private static let timeoutPeriod: Double = 15.0

    private let userId: Int
    private let accessQueue: DispatchQueue
    private let timerScheduler: ConcurrentDispatchQueueScheduler
    private let handler: SyncActionHandler
    private let updateDataSource: SyncUpdateDataSource
    private let progressHandler: SyncProgressHandler
    private let conflictDelays: [Int]
    /// Bool specifies whether a new sync is needed, SyncType and LibrarySyncType are types used for new sync
    let observable: PublishSubject<(SyncController.SyncType, SyncController.LibrarySyncType)?>

    private var queue: [Action]
    private var processingAction: Action?
    private var type: SyncType
    private var libraryType: LibrarySyncType
    /// Version returned by last object sync, used to check for version mismatches between object syncs
    private var lastReturnedVersion: Int?
    /// Array of non-fatal errors that happened during current sync
    private var nonFatalErrors: [Error]
    private var disposeBag: DisposeBag
    private var conflictRetries: Int
    private var timerDisposeBag: DisposeBag

    var isSyncing: Bool {
        return self.processingAction != nil || !self.queue.isEmpty
    }

    var progressObservable: BehaviorRelay<SyncProgress?> {
        return self.progressHandler.observable
    }

    init(userId: Int, handler: SyncActionHandler, updateDataSource: SyncUpdateDataSource, conflictDelays: [Int]) {
        self.userId = userId
        let accessQueue = DispatchQueue(label: "org.zotero.SyncAccessQueue", qos: .utility, attributes: .concurrent)
        self.accessQueue = accessQueue
        self.handler = handler
        self.updateDataSource = updateDataSource
        self.timerScheduler = ConcurrentDispatchQueueScheduler(queue: accessQueue)
        self.observable = PublishSubject()
        self.progressHandler = SyncProgressHandler()
        self.disposeBag = DisposeBag()
        self.queue = []
        self.nonFatalErrors = []
        self.type = .normal
        self.libraryType = .all
        self.timerDisposeBag = DisposeBag()
        self.conflictDelays = conflictDelays
        self.conflictRetries = 0
    }

    // MARK: - Sync management

    func start(type: SyncType, libraries: LibrarySyncType) {
        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            guard let `self` = self, !self.isSyncing else { return }
            DDLogInfo("--- Sync: starting ---")
            self.type = type
            self.libraryType = libraries
            self.progressHandler.reportNewSync()
            self.queue.append(contentsOf: self.createInitialActions(for: libraries))
            self.processNextAction()
        }
    }

    func cancel() {
        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            guard let `self` = self, self.isSyncing else { return }
            DDLogInfo("--- Sync: cancelled ---")
            self.disposeBag = DisposeBag()
            self.cleanup()
            self.report(fatalError: SyncError.cancelled)
        }
    }

    private func createInitialActions(for libraries: LibrarySyncType) -> [SyncController.Action] {
        switch libraries {
        case .all:
            return [.syncVersions(.user(self.userId, .myLibrary), .group, nil)]
        case .specific(let identifiers):
            var customLibrariesOnly = true
            for identifier in identifiers {
                if case .group = identifier {
                    customLibrariesOnly = false
                    break
                }
            }
            if customLibrariesOnly {
                return [.createLibraryActions(libraries, .automatic)]
            }
            return [.syncVersions(.user(self.userId, .myLibrary), .group, nil)]
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
            self.reportDelay = nil

            self.reportFinish(nonFatalErrors: errors)
            self.cleanup()
        }
    }

    private func abort(error: Error) {
        DDLogInfo("--- Sync: aborted ---")
        DDLogInfo("Error: \(error)")

        self.reportFinish?(.failure(error))
        self.reportFinish = nil
        self.reportDelay = nil

        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            guard let `self` = self else { return }
            self.report(fatalError: error)
            self.cleanup()
        }
    }

    private func cleanup() {
        self.processingAction = nil
        self.queue = []
        self.nonFatalErrors = []
        self.type = .normal
        self.lastReturnedVersion = nil
        self.conflictRetries = 0
        self.timerDisposeBag = DisposeBag()
    }

    // MARK: - Error handling

    private func report(fatalError: Error) {
        self.progressHandler.reportAbort(with: fatalError)

        if let syncError = fatalError as? SyncError, syncError == .uploadObjectConflict {
            // In case of this fatal error we retry the sync with special type. This error was most likely caused
            // by a bug (library version passed validation while object version didn't), so we try to fix it.
            self.observable.on(.next((.all, .all)))
        } else {
            // Other aborted syncs are not retried, they are fatal, so retry won't help
            self.observable.on(.next(nil))
        }
    }

    private func reportFinish(nonFatalErrors errors: [Error]) {
        self.progressHandler.reportFinish(with: errors)

        // If we have non-fatal errors the first time, we try to do the same sync as a retry. Maybe retrying in a while
        // will help us out. If retry sync doesn't help and we still have errors we schedule a new full sync.
        // If that doesn't help something is broken and we can't recover from it anyway, so we just stop.

        if errors.isEmpty {
            self.observable.on(.next(nil))
            return
        }

        if self.type == .retry {
            self.observable.on(.next((.all, .all)))
        } else {
            self.observable.on(.next((.retry, self.libraryType)))
        }
    }

    // MARK: - Queue management

    private func enqueue(actions: [Action], at index: Int? = nil, delay: Int? = nil) {
        if !actions.isEmpty {
            if let index = index {
                self.queue.insert(contentsOf: actions, at: index)
            } else {
                self.queue.append(contentsOf: actions)
            }
        }

        if let delay = delay, delay > 0 {
            self.reportDelay?(delay)
            Single<Int>.timer(.seconds(delay), scheduler: self.timerScheduler)
                       .subscribe(onSuccess: { [weak self] _ in
                           self?.processNextAction()
                       })
                       .disposed(by: self.timerDisposeBag)
        } else {
            self.processNextAction()
        }
    }

    private func removeAllActions(for library: Library) {
        while !self.queue.isEmpty {
            guard self.queue[0].library == library else { break }
            self.queue.removeFirst()
        }
    }

    private func removeAllDownloadActions(for library: Library) {
        while !self.queue.isEmpty {
            guard self.queue[0].library == library else { break }
            switch self.queue[0] {
            case .resolveConflict, .submitDeleteBatch, .submitWriteBatch:
                continue
            default: break
            }
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

    private func process(action: Action) {
        DDLogInfo("--- Sync: action ---")
        DDLogInfo("\(action)")
        switch action {
        case .createLibraryActions(let libraries, let options):
            self.processCreateLibraryActions(for: libraries, options: options)
        case .syncVersions(let library, let objectType, let version):
            if objectType == .group {
                self.progressHandler.reportGroupSync()
            } else {
                self.progressHandler.reportVersionsSync(for: library, object: objectType)
            }
            self.processSyncVersions(library: library, object: objectType, since: version)
        case .syncBatchToDb(let batch):
            self.processBatchSync(for: batch)
        case .storeVersion(let version, let library, let object):
            self.processStoreVersion(library: library, type: .object(object), version: version)
        case .syncDeletions(let library, let version):
            self.progressHandler.reportDeletions(for: library)
            self.processDeletionsSync(library: library, since: version)
        case .syncSettings(let library, let version):
            self.processSettingsSync(for: library, since: version)
        case .storeSettingsVersion(let version, let library):
            self.processStoreVersion(library: library, type: .settings, version: version)
        case .submitWriteBatch(let batch):
            self.processSubmitUpdate(for: batch)
        case .submitDeleteBatch(let batch):
            self.processSubmitDeletion(for: batch)
        case .resolveConflict(let key, let library):
            // TODO: - resolve conflict...
            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                self?.processNextAction()
            }
            break
        }
    }

    enum CreateLibraryActionsOptions {
        case automatic, onlyWrites, forceDownloads
    }

    private func processCreateLibraryActions(for libraries: LibrarySyncType, options: CreateLibraryActionsOptions) {
        let userId = self.userId
        let action: Single<[LibraryData]>
        switch libraries {
        case .all:
            action = self.handler.loadAllLibraryData()
        case .specific(let identifiers):
            action = self.handler.loadLibraryData(for: identifiers)
        }

        action.flatMap { libraryData -> Single<([(Library, Versions)], [LibraryIdentifier: String])> in
                  var libraryNames: [LibraryIdentifier: String] = [:]
                  var versionedLibraries: [(Library, Versions)] = []

                  for data in libraryData {
                      libraryNames[data.identifier] = data.name
                      switch data.identifier {
                      case .custom(let type):
                          versionedLibraries.append((.user(userId, type), data.versions))
                      case .group(let identifier):
                          versionedLibraries.append((.group(identifier), data.versions))
                      }
                  }

                  return Single.just((versionedLibraries, libraryNames))
              }
              .subscribe(onSuccess: { [weak self] data in
                  if options == .automatic {
                      // Other options are internal process of one sync, no need to report library names (again)
                      self?.performOnAccessQueue(flags: .barrier) { [weak self] in
                          self?.progressHandler.reportLibraryNames(data: data.1)
                      }
                  }
                  self?.finishCreateLibraryActions(with: .success((data.0, options)))
              }, onError: { [weak self] error in
                  self?.finishCreateLibraryActions(with: .failure(error))
              })
              .disposed(by: self.disposeBag)
    }

    private func finishCreateLibraryActions(with result: Result<([(Library, Versions)], CreateLibraryActionsOptions)>) {
        switch result {
        case .failure(let error):
            self.abort(error: SyncError.allLibrariesFetchFailed(error))

        case .success(let data):
            do {
                let actionData = try self.createLibraryActions(for: data)
                self.performOnAccessQueue(flags: .barrier) { [weak self] in
                    self?.enqueue(actions: actionData.0, at: actionData.1)
                }
            } catch let error {
                DDLogError("SyncController: could not read updates from db - \(error)")
                self.abort(error: SyncError.dbError)
            }
        }
    }

    private func createLibraryActions(for data: ([(Library, Versions)], CreateLibraryActionsOptions)) throws -> ([Action], Int?) {
        var allActions: [Action] = []
        for libraryData in data.0 {
            switch data.1 {
            case .forceDownloads:
                allActions.append(contentsOf: self.createDownloadActions(for: libraryData.0,
                                                                         versions: libraryData.1))
            case .onlyWrites, .automatic:
                let updates = try self.updateDataSource.updates(for: libraryData.0, versions: libraryData.1)
                let deletions = try self.updateDataSource.deletions(for: libraryData.0, versions: libraryData.1)
                if !updates.isEmpty || !deletions.isEmpty {
                    allActions.append(contentsOf: updates.map({ .submitWriteBatch($0) }))
                    allActions.append(contentsOf: deletions.map({ .submitDeleteBatch($0) }))
                } else if data.1 == .automatic {
                    allActions.append(contentsOf: self.createDownloadActions(for: libraryData.0,
                                                                             versions: libraryData.1))
                }
            }
        }
        let index: Int? = data.1 == .automatic ? nil : 0 // Forced downloads or writes are pushed to the beginning
                                                         // of the queue, because only currently running action
                                                         // can force downloads or writes
        return (allActions, index)
    }

    private func createDownloadActions(for library: Library, versions: Versions) -> [Action] {
        return [.syncSettings(library, versions.settings),
                .syncVersions(library, .collection, versions.collections),
                .syncVersions(library, .search, versions.searches),
                .syncVersions(library, .item, versions.items),
                .syncVersions(library, .trash, versions.trash),
                .syncDeletions(library, versions.deletions)]
    }

    private func processSyncVersions(library: Library, object: Object, since version: Int?) {
        self.handler.synchronizeVersions(for: library, object: object, since: version,
                                         current: self.lastReturnedVersion, syncType: self.type)
                    .subscribe(onSuccess: { [weak self] data in
                        self?.finishSyncVersionsAction(for: library, object: object, result: .success((data.1, data.0)))
                    }, onError: { [weak self] error in
                        self?.finishSyncVersionsAction(for: library, object: object, result: .failure(error))
                    })
                    .disposed(by: self.disposeBag)
    }

    private func finishSyncVersionsAction(for library: Library, object: Object,
                                          result: Result<([Any], Int)>) {
        switch result {
        case .success(let data):
            self.progressHandler.reportObjectCount(for: object, count: data.0.count)
            self.createBatchedActions(from: data.0, currentVersion: data.1, library: library, object: object)

        case .failure(let error):
            if let abortError = self.errorRequiresAbort(error) {
                self.abort(error: abortError)
                return
            }

            // 304 is not actually an error, so we need to check before next "if" so that we don't abort on 304 response
            if self.handleUnchangedFailureIfNeeded(for: error, library: library) { return }

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
                                      library: Library, object: Object) {
        let batches: [DownloadBatch]
        switch object {
        case .group:
            let batchData = self.createBatchGroups(for: keys, version: currentVersion, syncType: self.libraryType)
            batches = batchData.0
            // TODO: - report deleted groups?
        default:
            batches = self.createBatchObjects(for: keys, library: library, object: object, version: currentVersion)
        }

        var actions: [Action] = batches.map({ .syncBatchToDb($0) })
        if object == .group {
            actions.append(.createLibraryActions(self.libraryType, .automatic))
        } else if !actions.isEmpty {
            actions.append(.storeVersion(currentVersion, library, object))
        }

        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            if object != .group {
                self?.lastReturnedVersion = currentVersion
            }
            self?.enqueue(actions: actions, at: 0)
        }
    }

    private func createBatchGroups(for keys: [Any], version: Int, syncType: LibrarySyncType) -> ([DownloadBatch], [Int]) {
        var toSync: [Any] = []
        var missing: [Int] = []

        switch syncType {
        case .all:
            toSync = keys

        case .specific(let identifiers):
            guard let intKeys = keys as? [Int] else { return ([], []) }

            identifiers.forEach { identifier in
                switch identifier {
                case .group(let groupId):
                    if intKeys.contains(groupId) {
                        toSync.append(groupId)
                    } else {
                        missing.append(groupId)
                    }
                case .custom: break
                }
            }
        }

        let batches = toSync.map { DownloadBatch(library: .user(self.userId, .myLibrary), object: .group,
                                                 keys: [$0], version: version) }
        return (batches, missing)
    }

    private func createBatchObjects(for keys: [Any], library: Library,
                                    object: Object, version: Int) -> [DownloadBatch] {
        let maxBatchSize = DownloadBatch.maxCount
        var batchSize = 5
        var processed = 0
        var batches: [DownloadBatch] = []

        while processed < keys.count {
            let upperBound = min((keys.count - processed), batchSize) + processed
            let batchKeys = Array(keys[processed..<upperBound])

            batches.append(DownloadBatch(library: library, object: object, keys: batchKeys, version: version))

            processed += batchSize
            if batchSize < maxBatchSize {
                batchSize = min(batchSize * 2, maxBatchSize)
            }
        }

        return batches
    }

    private func processBatchSync(for batch: DownloadBatch) {
        self.handler.fetchAndStoreObjects(with: batch.keys, library: batch.library,
                                          object: batch.object, version: batch.version)
                    .subscribe(onSuccess: { [weak self] decodingData in
                        self?.finishBatchSyncAction(for: batch.library, object: batch.object,
                                                    allKeys: batch.keys, result: .success(decodingData))
                    }, onError: { [weak self] error in
                        self?.finishBatchSyncAction(for: batch.library, object: batch.object,
                                                    allKeys: batch.keys, result: .failure(error))
                    })
                    .disposed(by: self.disposeBag)
    }

    private func finishBatchSyncAction(for library: Library, object: Object, allKeys: [Any],
                                     result: Result<([String], [Error], [StoreItemsError])>) {
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

            let conflicts = decodingData.2.map({ error -> Action in
                switch error {
                case .itemDeleted(let response):
                    return .resolveConflict(response.key, library)
                }
            })
            let allStringKeys = (allKeys as? [String]) ?? []
            let failedKeys = allStringKeys.filter({ !decodingData.0.contains($0) })

            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                guard let `self` = self else { return }
                self.progressHandler.reportBatch(for: object, count: allKeys.count)
                self.queue.insert(contentsOf: conflicts, at: 0)
                if failedKeys.isEmpty {
                    self.processNextAction()
                }
            }

            if !failedKeys.isEmpty {
                self.markForResync(keys: Array(failedKeys), library: library, object: object)
            }

        case .failure(let error):
            DDLogError("--- BATCH: \(error)")
            if let abortError = self.errorRequiresAbort(error) {
                self.abort(error: abortError)
                return
            }

            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                self?.progressHandler.reportBatch(for: object, count: allKeys.count)
            }

            // We failed to sync the whole batch, mark all for resync and continue with sync
            self.markForResync(keys: allKeys, library: library, object: object)
        }
    }

    private func processStoreVersion(library: Library, type: UpdateVersionType, version: Int) {
        self.handler.storeVersion(version, for: library, type: type)
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

    private func markForResync(keys: [Any], library: Library, object: Object) {
        self.handler.markForResync(keys: keys, library: library, object: object)
                    .subscribe(onCompleted: { [weak self] in
                        self?.performOnAccessQueue(flags: .barrier) { [weak self] in
                            guard let `self` = self else { return }
                            self.processNextAction()
                        }
                    }, onError: { [weak self] error in
                        guard let `self` = self else { return }

                        if let abortError = self.errorRequiresAbort(error) {
                            self.abort(error: abortError)
                            return
                        }

                        self.performOnAccessQueue(flags: .barrier) { [weak self] in
                            guard let `self` = self else { return }
                            self.nonFatalErrors.append(error)
                            self.removeAllActions(for: library)
                            self.processNextAction()
                        }
                    })
                    .disposed(by: self.disposeBag)
    }

    private func processDeletionsSync(library: Library, since sinceVersion: Int) {
        self.handler.synchronizeDeletions(for: library, since: sinceVersion, current: self.lastReturnedVersion)
                    .subscribe(onSuccess: { [weak self] conflicts in
                        self?.finishDeletionsSync(result: .success(conflicts), library: library)
                    }, onError: { [weak self] error in
                        self?.finishDeletionsSync(result: .failure(error), library: library)
                    })
                    .disposed(by: self.disposeBag)
    }

    private func finishDeletionsSync(result: Result<[String]>, library: Library) {
        switch result {
        case .success(let conflicts):
            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                guard let `self` = self else { return }
                if !conflicts.isEmpty {
                    let actions: [Action] = conflicts.map({ .resolveConflict($0, library) })
                    self.queue.insert(contentsOf: actions, at: 0)
                }
                self.processNextAction()
            }

        case .failure(let error):
            if let abortError = self.errorRequiresAbort(error) {
                self.abort(error: abortError)
                return
            }

            if self.handleUnchangedFailureIfNeeded(for: error, library: library) { return }

            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                self?.nonFatalErrors.append(error)
                self?.processNextAction()
            }
        }
    }

    private func processSettingsSync(for library: Library, since version: Int?) {
        self.handler.synchronizeSettings(for: library, current: self.lastReturnedVersion, since: version)
                    .subscribe(onSuccess: { [weak self] data in
                        self?.performOnAccessQueue(flags: .barrier) { [weak self] in
                            if data.0 {
                                self?.enqueue(actions: [.storeSettingsVersion(data.1, library)], at: 0)
                            } else {
                                self?.processNextAction()
                            }
                        }
                    }, onError: { [weak self] error in
                        guard let `self` = self else { return }

                        if let abortError = self.errorRequiresAbort(error) {
                            self.abort(error: abortError)
                            return
                        }

                        if self.handleUnchangedFailureIfNeeded(for: error, library: library) { return }

                        self.performOnAccessQueue(flags: .barrier) { [weak self] in
                            self?.nonFatalErrors.append(error)
                            self?.processNextAction()
                        }
                    })
                    .disposed(by: self.disposeBag)
    }

    private func processSubmitUpdate(for batch: WriteBatch) {
        self.handler.submitUpdate(for: batch.library, object: batch.object,
                                  since: batch.version, parameters: batch.parameters)
                    .subscribe(onSuccess: { [weak self] data in
                        self?.finishSubmission(error: data.1, newVersion: data.0,
                                               library: batch.library, object: batch.object)
                    }, onError: { [weak self] error in
                        self?.finishSubmission(error: error, newVersion: batch.version,
                                               library: batch.library, object: batch.object)
                    })
                    .disposed(by: self.disposeBag)
    }

    private func processSubmitDeletion(for batch: DeleteBatch) {
        self.handler.submitDeletion(for: batch.library, object: batch.object, since: batch.version, keys: batch.keys)
                    .subscribe(onSuccess: { [weak self] version in
                        self?.finishSubmission(error: nil, newVersion: version,
                                               library: batch.library, object: batch.object)
                    }, onError: { [weak self] error in
                        self?.finishSubmission(error: error, newVersion: batch.version,
                                               library: batch.library, object: batch.object)
                    })
                    .disposed(by: self.disposeBag)
    }

    private func finishSubmission(error: Error?, newVersion: Int, library: Library, object: Object) {
        if let error = error {
            if self.handleUpdatePreconditionFailureIfNeeded(for: error, library: library) {
                return
            }

            if let error = self.errorRequiresAbort(error) {
                self.abort(error: error)
                return
            }
        }

        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            if let error = error {
                self?.nonFatalErrors.append(error)
            }
            self?.updateVersionInNextWriteBatch(to: newVersion)
            self?.processNextAction()
        }
    }

    // MARK: - Helpers

    private func updateVersionInNextWriteBatch(to version: Int) {
        guard let action = self.queue.first else { return }

        switch action {
        case .submitWriteBatch(let batch):
            let updatedBatch = batch.copy(withVersion: version)
            self.queue[0] = .submitWriteBatch(updatedBatch)
        case .submitDeleteBatch(let batch):
            let updatedBatch = batch.copy(withVersion: version)
            self.queue[0] = .submitDeleteBatch(updatedBatch)
        default: break
        }
    }

    private func performOnAccessQueue(flags: DispatchWorkItemFlags = [], action: @escaping () -> Void) {
        self.accessQueue.async(flags: flags) {
            action()
        }
    }

    private func errorRequiresAbort(_ error: Error) -> Error? {
        let nsError = error as NSError

        // Check connection
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorNotConnectedToInternet {
            return SyncError.noInternetConnection
        }

        // Check other networking errors
        if let responseError = error as? AFResponseError {
            return self.alamoErrorRequiresAbort(responseError.error)
        }
        if let alamoError = error as? AFError {
            return self.alamoErrorRequiresAbort(alamoError)
        }

        // Check realm errors, every "core" error is bad. Can't create new Realm instance, can't continue with sync
        if error is Realm.Error {
            return SyncError.dbError
        }

        return nil
    }

    private func alamoErrorRequiresAbort(_ error: AFError) -> SyncError? {
        switch error {
        case .responseValidationFailed(let reason):
            switch reason {
            case .unacceptableStatusCode(let code):
                return (code >= 400 && code <= 499 && code != 403) ? SyncError.apiError : nil
            case .dataFileNil, .dataFileReadFailed, .missingContentType, .unacceptableContentType:
                return SyncError.apiError
            }
        case .multipartEncodingFailed, .parameterEncodingFailed, .invalidURL:
            return SyncError.apiError
        case .responseSerializationFailed:
            return nil
        }
    }

    private func handleVersionMismatchIfNeeded(for error: Error, library: Library) -> Bool {
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

    private func handleUpdatePreconditionFailureIfNeeded(for error: Error, library: Library) -> Bool {
        guard let type = error.preconditionFailureType else { return false }

        // Remote has newer version than local, we need to remove remaining write actions for this library from queue,
        // sync remote changes and then try to upload our local changes again, we remove existing write actions from
        // queue because they might change - for example some deletions might be overwritten by remote changes

        switch type {
        case .objectConflict:
            self.abort(error: SyncError.uploadObjectConflict)

        case .libraryConflict:
            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                guard let `self` = self else { return }

                let delay = self.conflictDelays[min(self.conflictRetries, (self.conflictDelays.count - 1))]
                let actions: [Action] = [.createLibraryActions(.specific([library.libraryId]), .forceDownloads),
                                         .createLibraryActions(.specific([library.libraryId]), .onlyWrites)]

                self.conflictRetries += 1

                self.removeAllActions(for: library)
                self.enqueue(actions: actions, at: 0, delay: delay)
            }
        }

        return true
    }

    private func handleUnchangedFailureIfNeeded(for error: Error, library: Library) -> Bool {
        guard error.isUnchangedError else { return false }

        // If data is unchanged, we can skip all download actions for this library

        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            guard let `self` = self else { return }
            self.removeAllDownloadActions(for: library)
            self.processNextAction()
        }
        return true
    }

    // MARK: - Testing

    var reportFinish: ((Result<([Action], [Error])>) -> Void)?
    var reportDelay: ((Int) -> Void)?
    private var allActions: [Action] = []

    func start(with queue: [Action], libraries: LibrarySyncType,
               finishedAction: @escaping (Result<([Action], [Error])>) -> Void) {
        self.queue = queue
        self.libraryType = libraries
        self.allActions = []
        self.reportFinish = finishedAction
        self.processNextAction()
    }
}

enum PreconditionErrorType {
    case objectConflict, libraryConflict
}

extension Error {
    var isMismatchError: Bool {
        return (self as? SyncActionHandlerError) == .versionMismatch
    }

    var isUnchangedError: Bool {
        return self.afError.flatMap({ $0.statusCode == 304 }) ?? false
    }

    var preconditionFailureType: PreconditionErrorType? {
        if (self as? SyncActionHandlerError) == .objectConflict {
            return .objectConflict
        }
        if self.afError.flatMap({ $0.statusCode == 412 }) == true {
            return .libraryConflict
        }
        return nil
    }

    private var afError: AFError? {
        if let responseError = self as? AFResponseError {
            return responseError.error
        }
        if let alamoError = self as? AFError {
            return alamoError
        }
        return nil
    }
}

extension AFError {
    var statusCode: Int? {
        switch self {
        case .responseValidationFailed(let reason):
            switch reason {
            case .unacceptableStatusCode(let code):
                return code
            default: break
            }
        default: break
        }
        return nil
    }
}
