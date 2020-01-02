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
import RxAlamofire

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
    case permissionLoadingFailed
}

protocol SynchronizationController: class {
    var isSyncing: Bool { get }
    var observable: PublishSubject<(SyncController.SyncType, SyncController.LibrarySyncType)?> { get }
    var progressObservable: BehaviorRelay<SyncProgress?> { get }

    func start(type: SyncController.SyncType, libraries: SyncController.LibrarySyncType)
    func setConflictPresenter(_ presenter: ConflictPresenter)
    func cancel()
}

final class SyncController: SynchronizationController {
    enum SyncType {
        case normal                 // Only objects which need to be synced are fetched. Either synced objects
                                    // with old version or unsynced objects with backoff schedule.
        case ignoreIndividualDelays // Same as .normal, but individual backoff schedule is ignored.
        case all                    // All objects are fetched. Both individual backoff schedule and local versions are ignored.
    }

    enum LibrarySyncType: Equatable {
        case all                              // Syncs all libraries
        case specific([LibraryIdentifier])    // Syncs only specific libraries
    }

    enum Object: CaseIterable, Equatable {
        case group, collection, search, item, trash, tag
    }

    struct DownloadBatch: Equatable {
        static let maxCount = 50
        let libraryId: LibraryIdentifier
        let object: Object
        let keys: [Any]
        let version: Int

        // We don't really need equatability in this target, we need it for testing. Swift can't automatically
        // synthesize equatability function in an extension in a different file to the type. So I'm adding "placeholder"
        // equatability functions here so that Action equatability is synthesized automatically.
        static func ==(lhs: DownloadBatch, rhs: DownloadBatch) -> Bool {
            return true
        }
    }

    struct WriteBatch: Equatable {
        static let maxCount = 50
        let libraryId: LibraryIdentifier
        let object: Object
        let version: Int
        let parameters: [[String: Any]]

        func copy(withVersion version: Int) -> WriteBatch {
            return WriteBatch(libraryId: self.libraryId, object: self.object, version: version, parameters: self.parameters)
        }

        // We don't really need equatability in this target, we need it for testing. Swift can't automatically
        // synthesize equatability function in an extension in a different file to the type. So I'm adding "placeholder"
        // equatability functions here so that Action equatability is synthesized automatically.
        static func ==(lhs: WriteBatch, rhs: WriteBatch) -> Bool {
            return true
        }
    }

    struct AttachmentUpload: Equatable {
        let libraryId: LibraryIdentifier
        let key: String
        let filename: String
        let `extension`: String
        let md5: String
        let mtime: Int

        var file: File {
            return Files.objectFile(for: .item, libraryId: self.libraryId, key: self.key, ext: self.extension)
        }
    }

    struct DeleteBatch: Equatable {
        static let maxCount = 50
        let libraryId: LibraryIdentifier
        let object: Object
        let version: Int
        let keys: [String]

        func copy(withVersion version: Int) -> DeleteBatch {
            return DeleteBatch(libraryId: self.libraryId, object: self.object, version: version, keys: self.keys)
        }

        // We don't really need equatability in this target, we need it for testing. Swift can't automatically
        // synthesize equatability function in an extension in a different file to the type. So I'm adding "placeholder"
        // equatability functions here so that Action equatability is synthesized automatically.
        static func ==(lhs: DeleteBatch, rhs: DeleteBatch) -> Bool {
            return true
        }
    }

    enum CreateLibraryActionsOptions: Equatable {
        case automatic, onlyWrites, forceDownloads
    }

    struct AccessPermissions {
        struct Permissions {
            let library: Bool
            let notes: Bool
            let files: Bool
            let write: Bool
        }

        let user: Permissions
        let groupDefault: Permissions
        let groups: [Int: Permissions]
    }

    enum Action: Equatable {
        case loadKeyPermissions                                // Checks current key for access permissions
        case updateSchema                                      // Updates currently cached schema
        case syncVersions(LibraryIdentifier, Object, Int?)     // Fetch versions from API, update DB based on response
        case createLibraryActions(LibrarySyncType,             // Loads required libraries, spawn actions for each
                                  CreateLibraryActionsOptions)
        case createUploadActions(LibraryIdentifier)
        case syncBatchToDb(DownloadBatch)                      // Fetch data and store to db
        case storeVersion(Int, LibraryIdentifier, Object)      // Store new version for given library-object
        case syncDeletions(LibraryIdentifier, Int)             // Synchronize deletions of objects in library
        case syncSettings(LibraryIdentifier, Int?)             // Synchronize settings for library
        case storeSettingsVersion(Int, LibraryIdentifier)      // Store new version for settings in library
        case submitWriteBatch(WriteBatch)                      // Submit local changes to backend
        case uploadAttachment(AttachmentUpload)                // Upload local attachment to backend
        case submitDeleteBatch(DeleteBatch)                    // Submit local deletions to backend
        case resolveConflict(String, LibraryIdentifier)        // Handle conflict resolution
        case resolveDeletedGroup(Int, String)                  // Handle group that was deleted remotely - (Id, Name)
        case resolveGroupMetadataWritePermission(Int, String)  // Resolve when group had metadata editing allowed,
                                                               // but it was disabled and we try to upload new data
        case revertLibraryToOriginal(LibraryIdentifier)        // Revert all changes to original
                                                               // cached version of this group.
        case markChangesAsResolved(LibraryIdentifier)          // Local changes couldn't be written remotely, but we
                                                               // want to keep them locally anyway
        case deleteGroup(Int)                                  // Removes group from db
        case markGroupAsLocalOnly(Int)                         // Marks group as local only (not synced with backend)
    }

    private static let timeoutPeriod: Double = 15.0

    private let userId: Int
    private let accessQueue: DispatchQueue
    private let timerScheduler: ConcurrentDispatchQueueScheduler
    private let handler: SyncActionHandler
    private let progressHandler: SyncProgressHandler
    private let conflictDelays: [Int]
    /// Bool specifies whether a new sync is needed, SyncType and LibrarySyncType are types used for new sync
    let observable: PublishSubject<(SyncController.SyncType, SyncController.LibrarySyncType)?>

    private var queue: [Action]
    private var processingAction: Action?
    private var type: SyncType
    private var previousType: SyncType?
    private var libraryType: LibrarySyncType
    /// Version returned by last object sync, used to check for version mismatches between object syncs
    private var lastReturnedVersion: Int?
    /// Array of non-fatal errors that happened during current sync
    private var nonFatalErrors: [Error]
    private var disposeBag: DisposeBag
    private var conflictRetries: Int
    private var timerDisposeBag: DisposeBag
    private var accessPermissions: AccessPermissions?
    private var conflictReceiver: (ConflictReceiver & DebugPermissionReceiver)?

    var isSyncing: Bool {
        return self.processingAction != nil || !self.queue.isEmpty
    }

    var progressObservable: BehaviorRelay<SyncProgress?> {
        return self.progressHandler.observable
    }

    init(userId: Int, handler: SyncActionHandler, conflictDelays: [Int]) {
        self.userId = userId
        let accessQueue = DispatchQueue(label: "org.zotero.SyncAccessQueue", qos: .utility, attributes: .concurrent)
        self.accessQueue = accessQueue
        self.handler = handler
        self.timerScheduler = ConcurrentDispatchQueueScheduler(queue: accessQueue)
        self.observable = PublishSubject()
        self.progressHandler = SyncProgressHandler()
        self.disposeBag = DisposeBag()
        self.queue = []
        self.nonFatalErrors = []
        self.type = .normal
        self.previousType = nil
        self.libraryType = .all
        self.timerDisposeBag = DisposeBag()
        self.conflictDelays = conflictDelays
        self.conflictRetries = 0
    }

    func setConflictPresenter(_ presenter: ConflictPresenter) {
        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            self?.conflictReceiver = ConflictResolutionController(presenter: presenter)

            guard let `self` = self, let action = self.processingAction else { return }
            // ConflictReceiver was nil and we are waiting for CR action. Which means it was ignored previously and
            // we need to restart it.
            if action.requiresConflictReceiver || (Defaults.shared.askForSyncPermission && action.requiresDebugPermissionPrompt) {
                self.process(action: action)
            }
        }
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
            return [.loadKeyPermissions, .syncVersions(.custom(.myLibrary), .group, nil)]
        case .specific(let identifiers):
            for identifier in identifiers {
                if case .group = identifier {
                    return [.loadKeyPermissions, .syncVersions(.custom(.myLibrary), .group, nil)]
                }
            }
            return [.loadKeyPermissions, .createLibraryActions(libraries, .automatic)]
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
        self.accessPermissions = nil
    }

    // MARK: - Error handling

    private func report(fatalError: Error) {
        self.progressHandler.reportAbort(with: fatalError)
        self.previousType = nil

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

        if errors.isEmpty || self.type == .all {
            // We either have no errors and can finish or we already did full sync now and another one will probably not fix anything
            self.previousType = nil
            self.observable.on(.next(nil))
            return
        }

        let previousType = self.previousType
        self.previousType = self.type

        if previousType == nil {
            // There was no sync before this, so let's try the same sync again as a retry
            self.observable.on(.next((self.type, self.libraryType)))
        } else {
            // There was already a retry sync previously, so we try to run a full sync which might fix things
            self.observable.on(.next((.all, self.libraryType)))
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

    private func removeAllActions(for libraryId: LibraryIdentifier) {
        while !self.queue.isEmpty {
            guard self.queue.first?.libraryId == libraryId else { break }
            self.queue.removeFirst()
        }
    }

    private func removeAllDownloadActions(for libraryId: LibraryIdentifier) {
        while !self.queue.isEmpty {
            guard let action = self.queue.first, action.libraryId == libraryId else { break }
            switch action {
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
        if self.lastReturnedVersion != nil && action.libraryId != self.processingAction?.libraryId {
            self.lastReturnedVersion = nil
        }

        self.processingAction = action
        if Defaults.shared.askForSyncPermission && action.requiresDebugPermissionPrompt {
            self.askForUserPermission(action: action)
        } else {
            self.process(action: action)
        }
    }

    // MARK: - Action processing

    private func process(action: Action) {
        DDLogInfo("--- Sync: action ---")
        DDLogInfo("\(action)")
        switch action {
        case .loadKeyPermissions:
            self.processKeyCheckAction()
        case .updateSchema:
            self.updateSchema()
        case .createLibraryActions(let libraries, let options):
            self.processCreateLibraryActions(for: libraries, options: options)
        case .createUploadActions(let libraryId):
            self.processCreateUploadActions(for: libraryId)
        case .syncVersions(let libraryId, let objectType, let version):
            if objectType == .group {
                self.progressHandler.reportGroupSync()
            } else {
                self.progressHandler.reportVersionsSync(for: libraryId, object: objectType)
            }
            self.processSyncVersions(libraryId: libraryId, object: objectType, since: version)
        case .syncBatchToDb(let batch):
            self.processBatchSync(for: batch)
        case .storeVersion(let version, let libraryId, let object):
            self.processStoreVersion(libraryId: libraryId, type: .object(object), version: version)
        case .syncDeletions(let libraryId, let version):
            self.progressHandler.reportDeletions(for: libraryId)
            self.processDeletionsSync(libraryId: libraryId, since: version)
        case .syncSettings(let libraryId, let version):
            self.processSettingsSync(for: libraryId, since: version)
        case .storeSettingsVersion(let version, let libraryId):
            self.processStoreVersion(libraryId: libraryId, type: .settings, version: version)
        case .submitWriteBatch(let batch):
            self.processSubmitUpdate(for: batch)
        case .uploadAttachment(let upload):
            self.processUploadAttachment(for: upload)
        case .submitDeleteBatch(let batch):
            self.processSubmitDeletion(for: batch)
        case .deleteGroup(let groupId):
            self.deleteGroup(with: groupId)
        case .markGroupAsLocalOnly(let groupId):
            self.markGroupAsLocalOnly(with: groupId)
        case .revertLibraryToOriginal(let libraryId):
            self.revertGroupData(in: libraryId)
        case .markChangesAsResolved(let libraryId):
            self.markChangesAsResolved(in: libraryId)
        case .resolveConflict(let key, let libraryId):
            // TODO: - resolve conflict...
            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                self?.processNextAction()
            }
        case .resolveDeletedGroup(let groupId, let name):
            self.resolve(conflict: .groupRemoved(groupId, name))
        case .resolveGroupMetadataWritePermission(let groupId, let name):
            self.resolve(conflict: .groupWriteDenied(groupId, name))
        }
    }

    private func resolve(conflict: Conflict) {
        // If conflict receiver isn't yet assigned, we just wait for it and process current action when it's assigned
        // It's assigned either after login or shortly after app is launched, so we should never stay stuck on this.
        guard let receiver = self.conflictReceiver else { return }

        receiver.resolve(conflict: conflict) { [weak self] action in
            self?.performOnAccessQueue(flags: .barrier) {
                if let action = action {
                    self?.enqueue(actions: [action], at: 0)
                } else {
                    self?.processNextAction()
                }
            }
        }
    }

    /// This is used only for debugging purposes. Conflict receiver is used to ask for user permission whether current action can be performed.
    private func askForUserPermission(action: Action) {
        // If conflict receiver isn't yet assigned, we just wait for it and process current action when it's assigned
        // It's assigned either after login or shortly after app is launched, so we should never stay stuck on this.
        guard let receiver = self.conflictReceiver else { return }
        receiver.askForPermission(message: action.debugPermissionMessage) { response in
            switch response {
            case .allowed:
                self.process(action: action)
            case .cancelSync:
                self.cancel()
            case .skipAction:
                self.performOnAccessQueue(flags: .barrier) { [weak self] in
                    self?.processNextAction()
                }
            }
        }
    }

    private func processKeyCheckAction() {
        self.handler.loadPermissions().flatMap { (response, needsSchemaUpdate) -> Single<(AccessPermissions, String, Bool)> in
                                          let permissions = AccessPermissions(user: response.user,
                                                                              groupDefault: response.defaultGroup,
                                                                              groups: response.groups)
                                          return Single.just((permissions, response.username, needsSchemaUpdate))
                                      }
                                      .subscribe(onSuccess: { [weak self] permissions, username, needsSchemaUpdate in
                                          Defaults.shared.username = username
                                          self?.performOnAccessQueue(flags: .barrier) {
                                              self?.accessPermissions = permissions
                                              if needsSchemaUpdate {
                                                  self?.enqueue(actions: [.updateSchema], at: 0)
                                              } else {
                                                  self?.processNextAction()
                                              }
                                          }
                                      }, onError: { error in
                                          self.abort(error: SyncError.permissionLoadingFailed)
                                      })
                                      .disposed(by: self.disposeBag)
    }

    private func updateSchema() {
        self.handler.updateSchema()
                    .subscribe(onCompleted: { [weak self] in
                        self?.finishCompletableAction(error: nil)
                    }, onError: { [weak self] error in
                        self?.finishCompletableAction(error: error)
                    })
                    .disposed(by: self.disposeBag)
    }

    private func processCreateLibraryActions(for libraries: LibrarySyncType, options: CreateLibraryActionsOptions) {
        self.handler.loadLibraryData(for: libraries, fetchUpdates: (options != .forceDownloads))
                    .subscribe(onSuccess: { [weak self] data in
                        self?.finishCreateLibraryActions(with: .success((data, options)))
                    }, onError: { [weak self] error in
                        self?.finishCreateLibraryActions(with: .failure(error))
                    })
                    .disposed(by: self.disposeBag)
    }

    private func finishCreateLibraryActions(with result: Result<([LibraryData], CreateLibraryActionsOptions)>) {
        switch result {
        case .failure(let error):
            self.abort(error: SyncError.allLibrariesFetchFailed(error))

        case .success(let data, let options):
            var libraryNames: [LibraryIdentifier: String]?

            if options == .automatic {
                var nameDictionary: [LibraryIdentifier: String] = [:]
                // Other options are internal process of one sync, no need to report library names (again)
                for libraryData in data {
                    nameDictionary[libraryData.identifier] = libraryData.name
                }
                libraryNames = nameDictionary
            }

            do {
                let (actions, queueIndex) = try self.createLibraryActions(for: data, creationOptions: options)
                self.performOnAccessQueue(flags: .barrier) { [weak self] in
                    if let names = libraryNames {
                        self?.progressHandler.reportLibraryNames(data: names)
                    }
                    self?.enqueue(actions: actions, at: queueIndex)
                }
            } catch let error {
                DDLogError("SyncController: could not read updates from db - \(error)")
                self.abort(error: SyncError.dbError)
            }
        }
    }

    private func createLibraryActions(for data: [LibraryData],
                                      creationOptions: CreateLibraryActionsOptions) throws -> ([Action], Int?) {
        var allActions: [Action] = []
        for libraryData in data {
            let libraryId: LibraryIdentifier
            switch libraryData.identifier {
            case .custom(let type):
                libraryId = .custom(type)
            case .group(let identifier):
                libraryId = .group(identifier)
            }

            switch creationOptions {
            case .forceDownloads:
                allActions.append(contentsOf: self.createDownloadActions(for: libraryId,
                                                                         versions: libraryData.versions))
            case .onlyWrites, .automatic:
                if !libraryData.updates.isEmpty || !libraryData.deletions.isEmpty || libraryData.hasUpload {
                    switch libraryData.identifier {
                    case .group(let groupId):
                        // We need to check permissions for group
                        if libraryData.canEditMetadata {
                            allActions.append(contentsOf: self.createUpdateActions(updates: libraryData.updates,
                                                                                   deletions: libraryData.deletions,
                                                                                   libraryId: libraryId))
                        } else {
                            allActions.append(.resolveGroupMetadataWritePermission(groupId, libraryData.name))
                        }
                    case .custom:
                        // We can always write to custom libraries
                        allActions.append(contentsOf: self.createUpdateActions(updates: libraryData.updates,
                                                                               deletions: libraryData.deletions,
                                                                               libraryId: libraryId))
                    }
                } else if creationOptions == .automatic {
                    allActions.append(contentsOf: self.createDownloadActions(for: libraryId,
                                                                             versions: libraryData.versions))
                }
            }
        }
        let index: Int? = creationOptions == .automatic ? nil : 0 // Forced downloads or writes are pushed to the beginning
                                                                  // of the queue, because only currently running action
                                                                  // can force downloads or writes
        return (allActions, index)
    }

    private func createUpdateActions(updates: [WriteBatch], deletions: [DeleteBatch], libraryId: LibraryIdentifier) -> [Action] {
        var actions: [Action] = []
        if !updates.isEmpty {
            actions.append(contentsOf: updates.map({ .submitWriteBatch($0) }))
        }
        if !deletions.isEmpty {
            actions.append(contentsOf: deletions.map({ .submitDeleteBatch($0) }))
        }
        actions.append(.createUploadActions(libraryId))
        return actions
    }

    private func createDownloadActions(for libraryId: LibraryIdentifier, versions: Versions) -> [Action] {
        return [.syncSettings(libraryId, versions.settings),
                .syncVersions(libraryId, .collection, versions.collections),
                .syncVersions(libraryId, .search, versions.searches),
                .syncVersions(libraryId, .item, versions.items),
                .syncVersions(libraryId, .trash, versions.trash),
                .syncDeletions(libraryId, versions.deletions)]
    }

    private func processCreateUploadActions(for libraryId: LibraryIdentifier) {
        self.handler.loadUploadData(in: libraryId)
                    .subscribe(onSuccess: { [weak self] uploads in
                        self?.performOnAccessQueue(flags: .barrier) { [weak self] in
                            self?.enqueue(actions: uploads.map({ .uploadAttachment($0) }), at: 0)
                        }
                    }, onError: { [weak self] error in
                        self?.finishCompletableAction(error: error)
                    })
                    .disposed(by: self.disposeBag)
    }

    private func processSyncVersions(libraryId: LibraryIdentifier, object: Object, since version: Int?) {
        let userId = self.userId
        switch object {
        case .group:
            self.handler.synchronizeGroupVersions(libraryId: libraryId, userId: userId, syncType: self.type)
                        .subscribe(onSuccess: { [weak self] (version, toUpdate, toRemove) in
                            self?.progressHandler.reportObjectCount(for: .group, count: toUpdate.count)
                            self?.createBatchedGroupActions(updateIds: toUpdate, deleteGroups: toRemove, currentVersion: version)
                        }, onError: { [weak self] error in
                            self?.finishFailedSyncVersionsAction(libraryId: libraryId, object: object, error: error)
                        })
                        .disposed(by: self.disposeBag)
        default:
            self.handler.synchronizeVersions(for: libraryId, userId: userId, object: object, since: version,
                                             current: self.lastReturnedVersion, syncType: self.type)
                        .subscribe(onSuccess: { [weak self] (version, toUpdate) in
                            self?.progressHandler.reportObjectCount(for: object, count: toUpdate.count)
                            self?.createBatchedObjectActions(for: libraryId, object: object,
                                                             from: toUpdate, currentVersion: version)
                        }, onError: { [weak self] error in
                            self?.finishFailedSyncVersionsAction(libraryId: libraryId, object: object, error: error)
                        })
                        .disposed(by: self.disposeBag)
        }
    }

    private func finishFailedSyncVersionsAction(libraryId: LibraryIdentifier, object: Object, error: Error) {
        if let abortError = self.errorRequiresAbort(error) {
            self.abort(error: abortError)
            return
        }

        // 304 is not actually an error, so we need to check before next "if" so that we don't abort on 304 response
        if self.handleUnchangedFailureIfNeeded(for: error, libraryId: libraryId) { return }

        if object == .group {
            self.abort(error: SyncError.groupSyncFailed(error))
            return
        }

        if self.handleVersionMismatchIfNeeded(for: error, libraryId: libraryId) { return }

        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            guard let `self` = self else { return }
            self.nonFatalErrors.append(error)
            self.processNextAction()
        }
    }

    private func createBatchedObjectActions(for libraryId: LibraryIdentifier, object: Object,
                                            from keys: [Any], currentVersion: Int) {
        let batches = self.createBatchObjects(for: keys, libraryId: libraryId, object: object, version: currentVersion)

        var actions: [Action] = batches.map({ .syncBatchToDb($0) })
        if !actions.isEmpty {
            actions.append(.storeVersion(currentVersion, libraryId, object))
        }

        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            self?.lastReturnedVersion = currentVersion
            self?.enqueue(actions: actions, at: 0)
        }
    }

    private func createBatchedGroupActions(updateIds: [Int], deleteGroups: [(Int, String)], currentVersion: Int) {
        var idsToBatch: [Int]

        switch self.libraryType {
        case .all:
            idsToBatch = updateIds
        case .specific(let libraryIds):
            idsToBatch = []
            libraryIds.forEach { libraryId in
                switch libraryId {
                case .group(let groupId):
                    if updateIds.contains(groupId) {
                        idsToBatch.append(groupId)
                    }
                case .custom: break
                }
            }
        }

        let batches = idsToBatch.map({ DownloadBatch(libraryId: .custom(.myLibrary), object: .group,
                                                     keys: [$0], version: currentVersion) })
        var actions: [Action] = deleteGroups.map({ .resolveDeletedGroup($0.0, $0.1) })
        actions.append(contentsOf: batches.map({ .syncBatchToDb($0) }))
        actions.append(.createLibraryActions(self.libraryType, .automatic))

        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            self?.enqueue(actions: actions, at: 0)
        }
    }

    private func createBatchObjects(for keys: [Any], libraryId: LibraryIdentifier,
                                    object: Object, version: Int) -> [DownloadBatch] {
        let maxBatchSize = DownloadBatch.maxCount
        var batchSize = 5
        var processed = 0
        var batches: [DownloadBatch] = []

        while processed < keys.count {
            let upperBound = min((keys.count - processed), batchSize) + processed
            let batchKeys = Array(keys[processed..<upperBound])

            batches.append(DownloadBatch(libraryId: libraryId, object: object, keys: batchKeys, version: version))

            processed += batchSize
            if batchSize < maxBatchSize {
                batchSize = min(batchSize * 2, maxBatchSize)
            }
        }

        return batches
    }

    private func processBatchSync(for batch: DownloadBatch) {
        self.handler.fetchAndStoreObjects(with: batch.keys, libraryId: batch.libraryId,
                                          object: batch.object, version: batch.version, userId: self.userId)
                    .subscribe(onSuccess: { [weak self] decodingData in
                        self?.finishBatchSyncAction(for: batch.libraryId, object: batch.object,
                                                    allKeys: batch.keys, result: .success(decodingData))
                    }, onError: { [weak self] error in
                        self?.finishBatchSyncAction(for: batch.libraryId, object: batch.object,
                                                    allKeys: batch.keys, result: .failure(error))
                    })
                    .disposed(by: self.disposeBag)
    }

    private func finishBatchSyncAction(for libraryId: LibraryIdentifier, object: Object, allKeys: [Any],
                                     result: Result<([String], [Error], [StoreItemsError])>) {
        switch result {
        case .success(let ids, let parseErrors, let itemConflicts):
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

            // BETA: - no conflicts are created in beta, we prefer remote over everything local, so the itemConflicts
            // should be always empty now, but let's comment it just to be sure we don't unnecessarily create conflicts
            let conflicts: [Action] = []
//            let conflicts = itemConflicts.map({ conflict -> Action in
//                switch conflict {
//                case .itemDeleted(let response):
//                    return .resolveConflict(response.key, library)
//                case .itemChanged(let response):
//                    return .resolveConflict(response.key, library)
//                }
//            })
            let allStringKeys = (allKeys as? [String]) ?? []
            let failedKeys = allStringKeys.filter({ !ids.contains($0) })

            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                guard let `self` = self else { return }
                self.progressHandler.reportBatch(for: object, count: allKeys.count)
                if !conflicts.isEmpty {
                    self.queue.insert(contentsOf: conflicts, at: 0)
                }
                self.nonFatalErrors.append(contentsOf: parseErrors)
                if failedKeys.isEmpty {
                    self.processNextAction()
                }
            }

            if !failedKeys.isEmpty {
                self.markForResync(keys: Array(failedKeys), libraryId: libraryId, object: object)
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
            self.markForResync(keys: allKeys, libraryId: libraryId, object: object)
        }
    }

    private func processStoreVersion(libraryId: LibraryIdentifier, type: UpdateVersionType, version: Int) {
        self.handler.storeVersion(version, for: libraryId, type: type)
                    .subscribe(onCompleted: { [weak self] in
                        self?.finishCompletableAction(error: nil)
                    }, onError: { [weak self] error in
                        self?.finishCompletableAction(error: error)
                    })
                    .disposed(by: self.disposeBag)
    }

    private func markForResync(keys: [Any], libraryId: LibraryIdentifier, object: Object) {
        self.handler.markForResync(keys: keys, libraryId: libraryId, object: object)
                    .subscribe(onCompleted: { [weak self] in
                        self?.finishCompletableAction(error: nil)
                    }, onError: { [weak self] error in
                        self?.finishCompletableAction(error: error)
                    })
                    .disposed(by: self.disposeBag)
    }

    private func processDeletionsSync(libraryId: LibraryIdentifier, since sinceVersion: Int) {
        self.handler.synchronizeDeletions(for: libraryId, userId: self.userId, since: sinceVersion, current: self.lastReturnedVersion)
                    .subscribe(onSuccess: { [weak self] conflicts in
                        self?.finishDeletionsSync(result: .success(conflicts), libraryId: libraryId)
                    }, onError: { [weak self] error in
                        self?.finishDeletionsSync(result: .failure(error), libraryId: libraryId)
                    })
                    .disposed(by: self.disposeBag)
    }

    private func finishDeletionsSync(result: Result<[String]>, libraryId: LibraryIdentifier) {
        switch result {
        case .success(let conflicts):
            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                guard let `self` = self else { return }
                // BETA: - no conflicts are created in beta, we prefer remote over everything local, so the conflicts
                // should be always empty now, but let's comment it just to be sure we don't unnecessarily create conflicts
//                if !conflicts.isEmpty {
//                    let actions: [Action] = conflicts.map({ .resolveConflict($0, library) })
//                    self.queue.insert(contentsOf: actions, at: 0)
//                }
                self.processNextAction()
            }

        case .failure(let error):
            if let abortError = self.errorRequiresAbort(error) {
                self.abort(error: abortError)
                return
            }

            if self.handleUnchangedFailureIfNeeded(for: error, libraryId: libraryId) { return }

            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                self?.nonFatalErrors.append(error)
                self?.processNextAction()
            }
        }
    }

    private func processSettingsSync(for libraryId: LibraryIdentifier, since version: Int?) {
        self.handler.synchronizeSettings(for: libraryId, userId: self.userId, current: self.lastReturnedVersion, since: version)
                    .subscribe(onSuccess: { [weak self] (hasNewSettings, version) in
                        self?.performOnAccessQueue(flags: .barrier) { [weak self] in
                            if hasNewSettings {
                                self?.enqueue(actions: [.storeSettingsVersion(version, libraryId)], at: 0)
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

                        if self.handleUnchangedFailureIfNeeded(for: error, libraryId: libraryId) { return }

                        self.performOnAccessQueue(flags: .barrier) { [weak self] in
                            self?.nonFatalErrors.append(error)
                            self?.processNextAction()
                        }
                    })
                    .disposed(by: self.disposeBag)
    }

    private func processSubmitUpdate(for batch: WriteBatch) {
        self.handler.submitUpdate(for: batch.libraryId, userId: self.userId, object: batch.object,
                                  since: batch.version, parameters: batch.parameters)
                    .subscribe(onSuccess: { [weak self] (version, error) in
                        self?.finishSubmission(error: error, newVersion: version,
                                               libraryId: batch.libraryId, object: batch.object)
                    }, onError: { [weak self] error in
                        self?.finishSubmission(error: error, newVersion: batch.version,
                                               libraryId: batch.libraryId, object: batch.object)
                    })
                    .disposed(by: self.disposeBag)
    }

    private func processUploadAttachment(for upload: AttachmentUpload) {
        let (response, progress) = self.handler.uploadAttachment(for: upload.libraryId, userId: self.userId, key: upload.key, file: upload.file,
                                                                 filename: upload.filename, md5: upload.md5, mtime: upload.mtime)
        response.subscribe(onCompleted: { [weak self] in
                              self?.finishSubmission(error: nil, newVersion: nil,
                                                     libraryId: upload.libraryId, object: .item)
                          }, onError: { [weak self] error in
                              self?.finishSubmission(error: error, newVersion: nil,
                                                     libraryId: upload.libraryId, object: .item)
                          })
                          .disposed(by: self.disposeBag)

        // TODO: - observe upload progress in observers.1
    }

    private func processSubmitDeletion(for batch: DeleteBatch) {
        self.handler.submitDeletion(for: batch.libraryId, userId: self.userId, object: batch.object, since: batch.version, keys: batch.keys)
                    .subscribe(onSuccess: { [weak self] version in
                        self?.finishSubmission(error: nil, newVersion: version,
                                               libraryId: batch.libraryId, object: batch.object)
                    }, onError: { [weak self] error in
                        self?.finishSubmission(error: error, newVersion: batch.version,
                                               libraryId: batch.libraryId, object: batch.object)
                    })
                    .disposed(by: self.disposeBag)
    }

    private func finishSubmission(error: Error?, newVersion: Int?, libraryId: LibraryIdentifier, object: Object) {
        if let error = error {
            if self.handleUpdatePreconditionFailureIfNeeded(for: error, libraryId: libraryId) {
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
            if let version = newVersion {
                self?.updateVersionInNextWriteBatch(to: version)
            }
            self?.processNextAction()
        }
    }

    private func deleteGroup(with groupId: Int) {
        self.handler.deleteGroup(with: groupId)
                    .subscribe(onCompleted: { [weak self] in
                        self?.finishCompletableAction(error: nil)
                    }, onError: { [weak self] error in
                        self?.finishCompletableAction(error: error)
                    })
                    .disposed(by: self.disposeBag)
    }

    private func markGroupAsLocalOnly(with groupId: Int) {
        self.handler.markGroupAsLocalOnly(with: groupId)
                    .subscribe(onCompleted: { [weak self] in
                        self?.finishCompletableAction(error: nil)
                    }, onError: { [weak self] error in
                        self?.finishCompletableAction(error: error)
                    })
                    .disposed(by: self.disposeBag)
    }

    private func markChangesAsResolved(in libraryId: LibraryIdentifier) {
        self.handler.markChangesAsResolved(in: libraryId)
                    .subscribe(onCompleted: { [weak self] in
                        self?.finishCompletableAction(error: nil)
                    }, onError: { [weak self] error in
                        self?.finishCompletableAction(error: error)
                    })
                    .disposed(by: self.disposeBag)
    }

    private func revertGroupData(in libraryId: LibraryIdentifier) {
        self.handler.revertLibraryUpdates(in: libraryId)
                    .subscribe(onSuccess: { [weak self] failures in
                        // TODO: - report failures?
                        self?.finishCompletableAction(error: nil)
                    }, onError: { [weak self] error in
                        self?.finishCompletableAction(error: nil)
                    })
                    .disposed(by: self.disposeBag)
    }

    private func finishCompletableAction(error: Error?) {
        if let error = error.flatMap({ self.errorRequiresAbort($0) }) {
            self.abort(error: error)
            return
        }

        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            if let error = error {
                self?.nonFatalErrors.append(error)
            }
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

    private func handleVersionMismatchIfNeeded(for error: Error, libraryId: LibraryIdentifier) -> Bool {
        guard error.isMismatchError else { return false }

        // If the backend received higher version in response than from previous responses,
        // there was a change on backend and we'll probably have conflicts, abort this library
        // and continue with sync
        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            guard let `self` = self else { return }
            self.nonFatalErrors.append(error)
            self.removeAllActions(for: libraryId)
            self.processNextAction()
        }
        return true
    }

    private func handleUpdatePreconditionFailureIfNeeded(for error: Error, libraryId: LibraryIdentifier) -> Bool {
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
                let actions: [Action] = [.createLibraryActions(.specific([libraryId]), .forceDownloads),
                                         .createLibraryActions(.specific([libraryId]), .onlyWrites)]

                self.conflictRetries += 1

                self.removeAllActions(for: libraryId)
                self.enqueue(actions: actions, at: 0, delay: delay)
            }
        }

        return true
    }

    private func handleUnchangedFailureIfNeeded(for error: Error, libraryId: LibraryIdentifier) -> Bool {
        guard error.isUnchangedError else { return false }

        // If data is unchanged, we can skip all download actions for this library

        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            guard let `self` = self else { return }
            self.removeAllDownloadActions(for: libraryId)
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
        return self.afError.flatMap({ $0.responseCode == 304 }) ?? false
    }

    var preconditionFailureType: PreconditionErrorType? {
        if (self as? SyncActionHandlerError) == .objectConflict {
            return .objectConflict
        }
        if self.afError.flatMap({ $0.responseCode == 412 }) == true {
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
