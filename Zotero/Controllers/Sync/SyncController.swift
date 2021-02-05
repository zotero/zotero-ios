//
//  SyncController.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import CocoaLumberjackSwift
import RealmSwift
import RxCocoa
import RxSwift
import RxAlamofire

protocol SyncAction {
    associatedtype Result

    var result: Single<Result> { get }
}

protocol ConflictReceiver {
    func resolve(conflict: Conflict, completed: @escaping (ConflictResolution?) -> Void)
}

protocol DebugPermissionReceiver {
    func askForPermission(message: String, completed: @escaping (DebugPermissionResponse) -> Void)
}

typealias ConflictCoordinator = ConflictReceiver & DebugPermissionReceiver

protocol SynchronizationController: class {
    var inProgress: Bool { get }
    var libraryIdInProgress: LibraryIdentifier? { get }
    var progressObservable: PublishSubject<SyncProgress> { get }

    func start(type: SyncController.SyncType, libraries: SyncController.LibrarySyncType)
    func set(coordinator: ConflictCoordinator?)
    func cancel()
}

final class SyncController: SynchronizationController {
    /// Type of sync
    enum SyncType {
        /// Only objects which need to be synced are fetched. Either synced objects with old version or unsynced objects with backoff schedule.
        case normal
        /// Same as .normal, but individual backoff schedule is ignored.
        case ignoreIndividualDelays
        /// All objects are fetched. Both individual backoff schedule and local versions are ignored.
        case all
        /// Synchronize only collections.
        case collectionsOnly
    }

    /// Specifies which libraries need to be synced.
    enum LibrarySyncType: Equatable {
        /// All libraries will be synced.
        case all
        /// Only specified libraries will be synced.
        case specific([LibraryIdentifier])
    }

    /// Specifies which actions should be created for libraries.
    enum CreateLibraryActionsOptions: Equatable {
        /// Create all types of actions, which are needed.
        case automatic
        /// Create only "write" actions - item submission, uploads, etc.
        case onlyWrites
        /// Create only "download" actions - version check, item data, etc.
        case forceDownloads
    }

    /// Sync action represents a step that the synchronization controller needs to take.
    enum Action: Equatable {
        /// Checks current key for access permissions.
        case loadKeyPermissions
        /// Fetch group versions from API, update DB based on response.
        case syncGroupVersions
        /// Fetch `SyncObject` versions from API, update DB based on response.
        case syncVersions(libraryId: LibraryIdentifier, object: SyncObject, version: Int, checkRemote: Bool)
        /// Loads required libraries, spawns actions for each.
        case createLibraryActions(LibrarySyncType, CreateLibraryActionsOptions)
        /// Loads items that need upload, spawns actions for each.
        case createUploadActions(LibraryIdentifier)
        /// Starts `SyncBatchProcessor` which downloads and stores all batches.
        case syncBatchesToDb([DownloadBatch])
        /// Store new version for given library-object.
        case storeVersion(Int, LibraryIdentifier, SyncObject)
        /// Synchronize deletions of objects in library.
        case syncDeletions(LibraryIdentifier, Int)
        /// Synchronize settings for library.
        case syncSettings(LibraryIdentifier, Int)
        /// Store new version for settings in library.
        case storeSettingsVersion(Int, LibraryIdentifier)
        /// Submit local changes to backend.
        case submitWriteBatch(WriteBatch)
        /// Upload local attachment to backend.
        case uploadAttachment(AttachmentUpload)
        /// Submit local deletions to backend.
        case submitDeleteBatch(DeleteBatch)
        /// Handle conflict resolution.
        case resolveConflict(String, LibraryIdentifier)
        /// Handle group that was deleted remotely - (Id, Name).
        case resolveDeletedGroup(Int, String)
        /// Resolve when group had metadata editing allowed, but it was disabled and we try to upload new data.
        case resolveGroupMetadataWritePermission(Int, String)
        /// Revert all changes to original cached version of this group.
        case revertLibraryToOriginal(LibraryIdentifier)
        /// Local changes couldn't be written remotely, but we want to keep them locally anyway.
        case markChangesAsResolved(LibraryIdentifier)
        /// Removes group from db.
        case deleteGroup(Int)
        /// Marks group as local only (not synced with backend).
        case markGroupAsLocalOnly(Int)
        /// Fetch group data and store to db.
        case syncGroupToDb(Int)
    }

    // All access to local variables is performed on this queue.
    private let accessQueue: DispatchQueue
    // All processing of actions is performed on this queue.
    private let workQueue: DispatchQueue
    // All processing of actions is scheduled on this scheduler.
    private let workScheduler: ConcurrentDispatchQueueScheduler
    // Controllers
    private let apiClient: ApiClient
    private let dbStorage: DbStorage
    private let fileStorage: FileStorage
    private let schemaController: SchemaController
    private let dateParser: DateParser
    private let backgroundUploader: BackgroundUploader
    // Handler for reporting sync progress to observers.
    private let progressHandler: SyncProgressHandler
    // Id of currently logged in user.
    private let userId: Int
    // Delay for queue. In case of conflict the queue will wait this amount of second before trying to download remote changes and submitting local
    // changes again.
    private let conflictDelays: [Int]
    // Delay for syncing. Local objects won't try to sync again until the delay passes (based on count of retries).
    private let syncDelayIntervals: [Double]
    // SyncType and LibrarySyncType are types used for new sync, if available, otherwise sync is not needed.
    let observable: PublishSubject<(SyncController.SyncType, SyncController.LibrarySyncType)?>

    // Type of current sync.
    private var type: SyncType
    // Queue of sync actions.
    private var queue: [Action]
    // Current action in progress.
    private var processingAction: Action?
    // Type of previous sync. Used for figuring out resync policy.
    private var previousType: SyncType?
    // Sync type for libraries.
    private var libraryType: LibrarySyncType
    // Create action option
    private var createActionOptions: CreateLibraryActionsOptions
    // Version returned by last object sync, used to check for version mismatches between object syncs
    private var lastReturnedVersion: Int?
    // Array of non-fatal errors that happened during current sync
    private var nonFatalErrors: [SyncError.NonFatal]
    // DisposeBag is a var so that the sync can be cancelled.
    private var disposeBag: DisposeBag
    // Number of retries for conflicts. Used to calculate conflict delay for processing next action.
    private var conflictRetries: Int
    // Access permissions for current sync.
    private var accessPermissions: AccessPermissions?
    // Used for conflict resolution when user interaction is needed.
    private var conflictCoordinator: (ConflictReceiver & DebugPermissionReceiver)?
    // Used for syncing batches of objects in `.syncBatchesToDb` action
    private var batchProcessor: SyncBatchProcessor?

    private var isSyncing: Bool {
        return self.processingAction != nil || !self.queue.isEmpty
    }

    // MARK: - Testing

    var reportFinish: ((Result<([Action], [Error]), Error>) -> Void)?
    var reportDelay: ((Int) -> Void)?
    private var allActions: [Action] = []

    // MARK: - Lifecycle

    init(userId: Int, apiClient: ApiClient, dbStorage: DbStorage, fileStorage: FileStorage, schemaController: SchemaController,
         dateParser: DateParser, backgroundUploader: BackgroundUploader, syncDelayIntervals: [Double], conflictDelays: [Int]) {
        let accessQueue = DispatchQueue(label: "org.zotero.SyncController.accessQueue", qos: .userInteractive, attributes: .concurrent)
        let workQueue = DispatchQueue(label: "org.zotero.SyncController.workQueue", qos: .userInteractive, attributes: .concurrent)
        self.userId = userId
        self.accessQueue = accessQueue
        self.workQueue = workQueue
        self.workScheduler = ConcurrentDispatchQueueScheduler(queue: workQueue)
        self.observable = PublishSubject()
        self.progressHandler = SyncProgressHandler()
        self.disposeBag = DisposeBag()
        self.queue = []
        self.nonFatalErrors = []
        self.type = .normal
        self.previousType = nil
        self.createActionOptions = .automatic
        self.libraryType = .all
        self.conflictDelays = conflictDelays
        self.conflictRetries = 0
        self.apiClient = apiClient
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.schemaController = schemaController
        self.dateParser = dateParser
        self.backgroundUploader = backgroundUploader
        self.syncDelayIntervals = syncDelayIntervals
    }

    // MARK: - SynchronizationController

    var inProgress: Bool {
        return self.accessQueue.sync { [unowned self] in
            return self.progressHandler.inProgress
        }
    }

    var libraryIdInProgress: LibraryIdentifier? {
        return self.accessQueue.sync { [unowned self] in
            return self.progressHandler.libraryIdInProgress
        }
    }

    var progressObservable: PublishSubject<SyncProgress> {
        return self.progressHandler.observable
    }

    /// Sets coordinator for conflict resolution.
    func set(coordinator: ConflictCoordinator?) {
        self.accessQueue.async(flags: .barrier) { [weak self] in
            self?.conflictCoordinator = coordinator

            guard coordinator != nil, let action = self?.processingAction else { return }
            // ConflictReceiver was nil and we are waiting for CR action. Which means it was ignored previously and
            // we need to restart it.
            if action.requiresConflictReceiver || (Defaults.shared.askForSyncPermission && action.requiresDebugPermissionPrompt) {
                self?.workQueue.async {
                    self?.process(action: action)
                }
            }
        }
    }

    /// Start a new sync if another sync is not already in progress (current sync is not automatically cancelled).
    /// - parameter type: Type of sync. See `SyncType` documentation for more info.
    /// - parameter libraries: Specifies which libraries should be synced. See `LibrarySyncType` documentation for more info.
    func start(type: SyncType, libraries: LibrarySyncType) {
        self.accessQueue.async(flags: .barrier) { [weak self] in
            guard let `self` = self, !self.isSyncing else { return }

            DDLogInfo("--- Sync: starting ---")

            self.type = type
            self.libraryType = libraries
            self.progressHandler.reportNewSync()
            self.queue.append(contentsOf: self.createInitialActions(for: libraries))

            self.processNextAction()
        }
    }

    /// Cancels ongoing sync.
    func cancel() {
        self.accessQueue.async(flags: .barrier) { [weak self] in
            guard let `self` = self, self.isSyncing else { return }

            DDLogInfo("--- Sync: cancelled ---")

            self.cleanup()
            self.report(fatalError: .cancelled)
        }
    }

    // MARK: - Controls

    /// Finishes ongoing sync.
    private func finish() {
        DDLogInfo("--- Sync: finished ---")
        if !self.nonFatalErrors.isEmpty {
            DDLogInfo("Errors: \(self.nonFatalErrors)")
        }

        self.reportFinish?(.success((self.allActions, self.nonFatalErrors)))
        self.reportFinish = nil
        self.reportDelay = nil

        self.reportFinish(nonFatalErrors: self.nonFatalErrors)
        self.cleanup()
    }

    /// Aborts ongoing sync with given error.
    /// - parameter error: Error which will be reported as a reason for this abort.
    private func abort(error: SyncError.Fatal) {
        DDLogInfo("--- Sync: aborted ---")
        DDLogInfo("Error: \(error)")

        self.reportFinish?(.failure(error))
        self.reportFinish = nil
        self.reportDelay = nil

        self.report(fatalError: error)
        self.cleanup()
    }

    /// Cleans up helper variables for current sync.
    private func cleanup() {
        self.processingAction = nil
        self.queue = []
        self.nonFatalErrors = []
        self.type = .normal
        self.lastReturnedVersion = nil
        self.conflictRetries = 0
        self.disposeBag = DisposeBag()
        self.accessPermissions = nil
        self.batchProcessor = nil
        self.libraryType = .all
        self.createActionOptions = .automatic
    }

    // MARK: - Error handling

    /// Reports fatal error. Fatal error stops the sync and aborts it. Enqueues a new sync if needed.
    /// - parameter fatalError: Error to be reported.
    private func report(fatalError: SyncError.Fatal) {
        self.progressHandler.reportAbort(with: fatalError)
        self.previousType = nil

        switch fatalError {
        case .uploadObjectConflict:
            if self.type != .all || self.libraryType != .all {
                // In case of this fatal error we retry the sync with special type. This error was most likely caused
                // by a bug (library version passed validation while object version didn't), so we try to fix it.
                self.observable.on(.next((.all, .all)))
            } else {
                // If this sync already was full sync, we can't do anything else.
                self.observable.on(.next(nil))
            }
        default:
            // Other aborted syncs are not retried, they are fatal, so retry won't help
            self.observable.on(.next(nil))
        }
    }

    /// Reports non-fatal errors. These happened during sync, but didn't need to stop it. Enqueues a new sync if needed.
    private func reportFinish(nonFatalErrors errors: [SyncError.NonFatal]) {
        self.progressHandler.reportFinish(with: errors)

        if errors.isEmpty || self.hasOnlySchemaErrors(in: errors) || self.type == .all {
            // We either have no errors and can finish or
            // there were only schema-related errors which won't be fixed by another sync or
            // we already did full sync now and another one will not fix anything
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

    private func hasOnlySchemaErrors(in errors: [SyncError.NonFatal]) -> Bool {
        for error in errors {
            switch error {
            case .schema: continue
            default: return false
            }
        }
        return true
    }

    // MARK: - Queue management

    /// Enqueues new actions and starts processing next action.
    /// - parameter actions: Array of actions to be added.
    /// - parameter index: Index in array where actions should be added. If nil, they will be appended.
    /// - parameter delay: Delay for processing new action.
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
            Single<Int>.timer(.seconds(delay), scheduler: self.workScheduler)
                       .subscribe(onSuccess: { [weak self] _ in
                           self?.accessQueue.async(flags: .barrier) {
                               self?.processNextAction()
                           }
                       })
                       .disposed(by: self.disposeBag)
        } else {
            self.processNextAction()
        }
    }

    /// Removes all actions for given library from the beginning of the queue.
    /// - parameter libraryId: Library identifier for which actions will be deleted.
    private func removeAllActions(for libraryId: LibraryIdentifier) {
        while !self.queue.isEmpty {
            guard self.queue.first?.libraryId == libraryId else { break }
            self.queue.removeFirst()
        }
    }

    /// Processes next action in queue.
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
            self.workQueue.async {
                self.process(action: action)
            }
        }
    }

    // MARK: - Action processing

    /// Processes given action.
    /// - parameter action: Action to process
    private func process(action: Action) {
        DDLogInfo("--- Sync: action ---")
        DDLogInfo("\(action)")

        switch action {
        case .loadKeyPermissions:
            self.processKeyCheckAction()
        case .createLibraryActions(let libraries, let options):
            self.processCreateLibraryActions(for: libraries, options: options)
        case .createUploadActions(let libraryId):
            self.processCreateUploadActions(for: libraryId)
        case .syncGroupVersions:
            self.progressHandler.reportGroupsSync()
            self.processSyncGroupVersions()
        case .syncVersions(let libraryId, let objectType, let version, let checkRemote):
            self.progressHandler.reportObjectSync(for: objectType, in: libraryId)
            self.processSyncVersions(libraryId: libraryId, object: objectType, since: version, checkRemote: checkRemote)
        case .syncBatchesToDb(let batches):
            self.processBatchesSync(for: batches)
        case .syncGroupToDb(let groupId):
            self.processGroupSync(groupId: groupId)
        case .storeVersion(let version, let libraryId, let object):
            self.processStoreVersion(libraryId: libraryId, type: .object(object), version: version)
        case .syncDeletions(let libraryId, let version):
            self.progressHandler.reportDeletions(for: libraryId)
            self.processDeletionsSync(libraryId: libraryId, since: version)
        case .syncSettings(let libraryId, let version):
            self.progressHandler.reportLibrarySync(for: libraryId)
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
        case .resolveConflict://(let key, let libraryId):
            // TODO: - resolve conflict...
            self.processNextAction()
        case .resolveDeletedGroup(let groupId, let name):
            self.resolve(conflict: .groupRemoved(groupId, name))
        case .resolveGroupMetadataWritePermission(let groupId, let name):
            self.resolve(conflict: .groupWriteDenied(groupId, name))
        }
    }

    /// Asks conflict receiver to resolve a conflict. Enqueues actions for given conflict resolution.
    /// - parameter conflict: Conflict to resolve.
    private func resolve(conflict: Conflict) {
        // If conflict receiver isn't yet assigned, we just wait for it and process current action when it's assigned
        // It's assigned either after login or shortly after app is launched, so we should never stay stuck on this.
        guard let receiver = self.conflictCoordinator else { return }

        receiver.resolve(conflict: conflict) { [weak self] resolution in
            self?.accessQueue.async(flags: .barrier) {
                guard let `self` = self else { return }
                if let resolution = resolution {
                    self.enqueue(actions: self.actions(for: resolution), at: 0)
                } else {
                    self.processNextAction()
                }
            }
        }
    }

    private func actions(for resolution: ConflictResolution) -> [Action] {
        switch resolution {
        case .deleteGroup(let id):
            return [.deleteGroup(id)]
        case .markChangesAsResolved(let id):
            return [.markChangesAsResolved(id)]
        case .markGroupAsLocalOnly(let id):
            return [.markGroupAsLocalOnly(id)]
        case .revertLibraryToOriginal(let id):
            return [.revertLibraryToOriginal(id)]
        }
    }

    /// Create initial actions for a sync. All sync will have key/permission sync. Then if a group needs to be synced
    /// (so libraries are either .all, or .specific contains a group id), then sync group metadata. If only my library is synced, after
    /// key sync jump straight to .createLibraryActions.
    /// - parameter libraries: Specifies which libraries need to sync.
    /// - returns: Initial ations for a new sync.
    private func createInitialActions(for libraries: LibrarySyncType) -> [SyncController.Action] {
        switch libraries {
        case .all:
            return [.loadKeyPermissions, .syncGroupVersions]
        case .specific(let identifiers):
            // If there is a group to be synced, sync group metadata as well
            for identifier in identifiers {
                if case .group = identifier {
                    return [.loadKeyPermissions, .syncGroupVersions]
                }
            }
            // If only my library is being synced, skip group metadata sync
            return [.loadKeyPermissions, .createLibraryActions(libraries, .automatic)]
        }
    }

    /// This is used only for debugging purposes. Conflict receiver is used to ask for user permission whether current action can be performed.
    private func askForUserPermission(action: Action) {
        // If conflict receiver isn't yet assigned, we just wait for it and process current action when it's assigned
        // It's assigned either after login or shortly after app is launched, so we should never stay stuck on this.
        guard let receiver = self.conflictCoordinator else { return }
        receiver.askForPermission(message: action.debugPermissionMessage) { response in
            switch response {
            case .allowed:
                self.workQueue.async { [weak self] in
                    self?.process(action: action)
                }
            case .cancelSync:
                self.cancel()
            case .skipAction:
                self.accessQueue.async(flags: .barrier) { [weak self] in
                    self?.processNextAction()
                }
            }
        }
    }

    private func processKeyCheckAction() {
        let result = LoadPermissionsSyncAction(apiClient: self.apiClient, queue: self.workQueue, scheduler: self.workScheduler).result
        result.subscribeOn(self.workScheduler)
              .flatMap { response -> Single<(AccessPermissions, String)> in
                  let permissions = AccessPermissions(user: response.user,
                                                      groupDefault: response.defaultGroup,
                                                      groups: response.groups)

                  if let group = permissions.groupDefault, (!group.library || !group.write) {
                      return Single.error(SyncError.Fatal.missingGroupPermissions)
                  }
                  return Single.just((permissions, response.username))
              }
              .subscribe(onSuccess: { [weak self] permissions, username in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      Defaults.shared.username = username
                      self?.accessPermissions = permissions
                      self?.processNextAction()
                  }
              }, onError: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                    self?.abort(error: ((error as? SyncError.Fatal) ?? .permissionLoadingFailed))
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func processCreateLibraryActions(for libraries: LibrarySyncType, options: CreateLibraryActionsOptions) {
        let result = LoadLibraryDataSyncAction(type: libraries, fetchUpdates: (options != .forceDownloads), dbStorage: self.dbStorage).result
        result.subscribeOn(self.workScheduler)
              .subscribe(onSuccess: { [weak self] data in
                  self?.finishCreateLibraryActions(with: .success((data, options)))
              }, onError: { [weak self] error in
                  self?.finishCreateLibraryActions(with: .failure(error))
              })
              .disposed(by: self.disposeBag)
    }

    private func finishCreateLibraryActions(with result: Result<([LibraryData], CreateLibraryActionsOptions), Error>) {
        switch result {
        case .failure(let error):
            self.accessQueue.async(flags: .barrier) { [weak self] in
                self?.abort(error: .allLibrariesFetchFailed(error))
            }

        case .success((let data, let options)):
            var libraryNames: [LibraryIdentifier: String]?

            if options == .automatic {
                var nameDictionary: [LibraryIdentifier: String] = [:]
                // Other options are internal process of one sync, no need to report library names (again)
                for libraryData in data {
                    nameDictionary[libraryData.identifier] = libraryData.name
                }
                libraryNames = nameDictionary
            }
            let (actions, queueIndex, writeCount) = self.createLibraryActions(for: data, creationOptions: options)

            self.accessQueue.async(flags: .barrier) { [weak self] in
                self?.createActionOptions = options
                if let names = libraryNames {
                    self?.progressHandler.set(libraryNames: names)
                }
                if writeCount > 0 {
                    self?.progressHandler.reportWrite(count: writeCount)
                }
                self?.enqueue(actions: actions, at: queueIndex)
            }
        }
    }

    private func createLibraryActions(for data: [LibraryData], creationOptions: CreateLibraryActionsOptions) -> ([Action], Int?, Int) {
        var writeCount = 0
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
                allActions.append(contentsOf: self.createDownloadActions(for: libraryId, versions: libraryData.versions))
            case .onlyWrites, .automatic:
                if !libraryData.updates.isEmpty || !libraryData.deletions.isEmpty || libraryData.hasUpload {
                    switch libraryData.identifier {
                    case .group(let groupId):
                        // We need to check permissions for group
                        if libraryData.canEditMetadata {
                            let actions = self.createUpdateActions(updates: libraryData.updates,
                                                                   deletions: libraryData.deletions,
                                                                   libraryId: libraryId)
                            writeCount += actions.count
                            allActions.append(contentsOf: actions)
                        } else {
                            allActions.append(.resolveGroupMetadataWritePermission(groupId, libraryData.name))
                        }
                    case .custom:
                        let actions = self.createUpdateActions(updates: libraryData.updates, deletions: libraryData.deletions, libraryId: libraryId)
                         writeCount += actions.count
                        // We can always write to custom libraries
                        allActions.append(contentsOf: actions)
                    }
                } else if creationOptions == .automatic {
                    allActions.append(contentsOf: self.createDownloadActions(for: libraryId, versions: libraryData.versions))
                }
            }
        }

        // Forced downloads or writes are pushed to the beginning of the queue, because only currently running action
        // can force downloads or writes
        let index: Int? = creationOptions == .automatic ? nil : 0
        return (allActions, index, writeCount)
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
        switch self.type {
        case .collectionsOnly:
            return [.syncVersions(libraryId: libraryId, object: .collection, version: versions.collections, checkRemote: true)]
        default:
            return [.syncSettings(libraryId, versions.settings),
                    .syncVersions(libraryId: libraryId, object: .collection, version: versions.collections, checkRemote: true),
    //                .syncVersions(libraryId, .search, versions.searches),
                    .syncVersions(libraryId: libraryId, object: .item, version: versions.items, checkRemote: true),
                    .syncVersions(libraryId: libraryId, object: .trash, version: versions.trash, checkRemote: true),
                    .syncDeletions(libraryId, versions.deletions)]
        }
    }

    private func processCreateUploadActions(for libraryId: LibraryIdentifier) {
        let result = LoadUploadDataSyncAction(libraryId: libraryId, backgroundUploader: self.backgroundUploader, dbStorage: self.dbStorage).result
        result.subscribeOn(self.workScheduler)
              .subscribe(onSuccess: { [weak self] uploads in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.progressHandler.reportUpload(count: uploads.count)
                      self?.enqueue(actions: uploads.map({ .uploadAttachment($0) }), at: 0)
                  }
              }, onError: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: error)
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func processSyncGroupVersions() {
        let result = SyncGroupVersionsSyncAction(syncType: self.type, userId: self.userId,
                                                 apiClient: self.apiClient, dbStorage: self.dbStorage,
                                                 queue: self.workQueue, scheduler: self.workScheduler).result
        result.subscribeOn(self.workScheduler)
              .subscribe(onSuccess: { [weak self] toUpdate, toRemove in
                  guard let `self` = self else { return }
                  let actions = self.createGroupActions(updateIds: toUpdate, deleteGroups: toRemove)
                  self.accessQueue.async(flags: .barrier) { [weak self] in
                    self?.finishSyncGroupVersions(actions: actions, updateCount: toUpdate.count)
                  }
              }, onError: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishFailedSyncGroupVersions(error: error)
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func finishSyncGroupVersions(actions: [Action], updateCount: Int) {
        self.progressHandler.reportGroupCount(count: updateCount)
        self.enqueue(actions: actions, at: 0)
    }

    private func createGroupActions(updateIds: [Int], deleteGroups: [(Int, String)]) -> [Action] {
        var idsToSync: [Int]

        switch self.libraryType {
        case .all:
            idsToSync = updateIds
        case .specific(let libraryIds):
            idsToSync = []
            libraryIds.forEach { libraryId in
                switch libraryId {
                case .group(let groupId):
                    if updateIds.contains(groupId) {
                        idsToSync.append(groupId)
                    }
                case .custom: break
                }
            }
        }

        var actions: [Action] = deleteGroups.map({ .resolveDeletedGroup($0.0, $0.1) })
        actions.append(contentsOf: idsToSync.map({ .syncGroupToDb($0) }))
        actions.append(.createLibraryActions(self.libraryType, .automatic))
        return actions
    }

    private func finishFailedSyncGroupVersions(error: Error) {
        switch self.syncError(from: error) {
        case .fatal(let error):
            self.abort(error: error)
        case .nonFatal:
            self.abort(error: .groupSyncFailed(error))
        }
    }

    private func processSyncVersions(libraryId: LibraryIdentifier, object: SyncObject, since version: Int, checkRemote: Bool) {
        let lastVersion = self.lastReturnedVersion
        let result = SyncVersionsSyncAction(object: object, sinceVersion: version, currentVersion: lastVersion,
                                            syncType: self.type, libraryId: libraryId, userId: self.userId,
                                            syncDelayIntervals: self.syncDelayIntervals, checkRemote: checkRemote,
                                            apiClient: self.apiClient, dbStorage: self.dbStorage,
                                            queue: self.workQueue, scheduler: self.workScheduler).result
        result.subscribeOn(self.workScheduler)
              .subscribe(onSuccess: { [weak self] newVersion, toUpdate in
                  guard let `self` = self else { return }
                  let versionDidChange = version != lastVersion
                  let actions = self.createBatchedObjectActions(for: libraryId, object: object, from: toUpdate,
                                                                version: newVersion, shouldStoreVersion: versionDidChange)
                  self.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishSyncVersions(actions: actions, updateCount: toUpdate.count, object: object, libraryId: libraryId)
                  }
              }, onError: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishFailedSyncVersions(libraryId: libraryId, object: object, error: error)
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func finishSyncVersions(actions: [Action], updateCount: Int, object: SyncObject, libraryId: LibraryIdentifier) {
        self.progressHandler.reportDownloadCount(for: object, count: updateCount, in: libraryId)
        self.enqueue(actions: actions, at: 0)
    }

    private func createBatchedObjectActions(for libraryId: LibraryIdentifier, object: SyncObject, from keys: [String], version: Int, shouldStoreVersion: Bool) -> [Action] {
        let batches = self.createBatchObjects(for: keys, libraryId: libraryId, object: object, version: version)

        guard !batches.isEmpty else { return [] }

        var actions: [Action] = [.syncBatchesToDb(batches)]
        if shouldStoreVersion {
            actions.append(.storeVersion(version, libraryId, object))
        }
        return actions
    }

    private func createBatchObjects(for keys: [String], libraryId: LibraryIdentifier, object: SyncObject, version: Int) -> [DownloadBatch] {
        let maxBatchSize = DownloadBatch.maxCount
        var batchSize = 10
        var lowerBound = 0
        var batches: [DownloadBatch] = []

        while lowerBound < keys.count {
            let upperBound = min((keys.count - lowerBound), batchSize) + lowerBound
            let batchKeys = Array(keys[lowerBound..<upperBound])

            batches.append(DownloadBatch(libraryId: libraryId, object: object, keys: batchKeys, version: version))

            lowerBound += batchSize
            if batchSize < maxBatchSize {
                batchSize = min(batchSize * 2, maxBatchSize)
            }
        }

        return batches
    }

    private func finishFailedSyncVersions(libraryId: LibraryIdentifier, object: SyncObject, error: Error) {
        if self.handleUnchangedFailureIfNeeded(for: error, libraryId: libraryId) { return }

        switch self.syncError(from: error) {
        case .fatal(let error):
            self.abort(error: error)
        case .nonFatal(let error):
            switch error {
            case .versionMismatch:
                self.handleVersionMismatch(for: libraryId)
            default:
                self.nonFatalErrors.append(error)
                self.processNextAction()
            }
        }
    }

    private func processBatchesSync(for batches: [DownloadBatch]) {
        guard let batch = batches.first else {
            self.accessQueue.async(flags: .barrier) { [weak self] in
                self?.processNextAction()
            }
            return
        }

        let libraryId = batch.libraryId
        let object = batch.object

        self.batchProcessor = SyncBatchProcessor(batches: batches, userId: self.userId, apiClient: self.apiClient,
                                                 dbStorage: self.dbStorage, fileStorage: self.fileStorage, schemaController: self.schemaController,
                                                 dateParser: self.dateParser, progress: { [weak self] processed in
                                                    self?.accessQueue.async(flags: .barrier) {
                                                        self?.progressHandler.reportDownloadBatchSynced(size: processed, for: object, in: libraryId)
                                                    }
                                                 },
                                                 completion: { [weak self] result in
                                                    self?.accessQueue.async(flags: .barrier) {
                                                        self?.batchProcessor = nil
                                                        self?.finishBatchesSyncAction(for: libraryId, object: object, result: result)
                                                    }
                                                 })
        self.batchProcessor?.start()
    }

    private func finishBatchesSyncAction(for libraryId: LibraryIdentifier, object: SyncObject, result: Swift.Result<SyncBatchResponse, Error>) {
        switch result {
        case .success((let failedKeys, let parseErrors, _))://let itemConflicts)):
            self.nonFatalErrors.append(contentsOf: parseErrors.map({ self.nonFatalError(from: $0) }))

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

            if !conflicts.isEmpty {
                self.queue.insert(contentsOf: conflicts, at: 0)
            }
            if failedKeys.isEmpty {
                self.processNextAction()
            } else {
                self.workQueue.async { [weak self] in
                    self?.markForResync(keys: Array(failedKeys), libraryId: libraryId, object: object)
                }
            }

        case .failure(let error):
            DDLogError("--- BATCH: \(error)")

            switch self.syncError(from: error) {
            case .fatal(let error):
                self.abort(error: error)
            case .nonFatal(let error):
                // We failed with non-fatal error. When all batches fail to sync, it's most likely a fatal error. Just to be sure, let's skip
                // this library and continue with sync.
                self.removeAllActions(for: libraryId)
                self.nonFatalErrors.append(error)
                self.processNextAction()
            }
        }
    }

    private func processGroupSync(groupId: Int) {
        let result = FetchAndStoreGroupSyncAction(identifier: groupId, userId: self.userId,
                                                  apiClient: self.apiClient, dbStorage: self.dbStorage,
                                                  queue: self.workQueue, scheduler: self.workScheduler).result
        result.subscribeOn(self.workScheduler)
              .subscribe(onSuccess: { [weak self] result in
                  self?.finishGroupSyncAction(for: groupId, error: nil)
              }, onError: { [weak self] error in
                  self?.finishGroupSyncAction(for: groupId, error: error)
              })
              .disposed(by: self.disposeBag)
    }

    private func finishGroupSyncAction(for identifier: Int, error: Error?) {
        guard let error = error else {
            self.accessQueue.async(flags: .barrier) { [weak self] in
                self?.progressHandler.reportGroupSynced()
                self?.processNextAction()
            }
            return
        }

        DDLogError("--- GROUP SYNC: \(error)")

        switch self.syncError(from: error) {
        case .fatal(let error):
            self.accessQueue.async(flags: .barrier) { [weak self] in
                self?.abort(error: error)
            }
        case .nonFatal(let error):
            self.accessQueue.async(flags: .barrier) { [weak self] in
                self?.nonFatalErrors.append(error)
                self?.progressHandler.reportGroupSynced()
            }
            self.markGroupForResync(identifier: identifier)
        }
    }

    private func processStoreVersion(libraryId: LibraryIdentifier, type: UpdateVersionType, version: Int) {
        let result = StoreVersionSyncAction(version: version, type: type, libraryId: libraryId, dbStorage: self.dbStorage).result
        result.subscribeOn(self.workScheduler)
              .subscribe(onSuccess: { [weak self] _ in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: nil)
                  }
              }, onError: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: error)
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func markGroupForResync(identifier: Int) {
        let result = MarkGroupForResyncSyncAction(identifier: identifier, dbStorage: self.dbStorage).result
        result.subscribeOn(self.workScheduler)
              .subscribe(onSuccess: { [weak self] _ in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: nil)
                  }
              }, onError: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: error)
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func markForResync(keys: [Any], libraryId: LibraryIdentifier, object: SyncObject) {
        let result = MarkForResyncSyncAction(keys: keys, object: object, libraryId: libraryId, dbStorage: self.dbStorage).result
        result.subscribeOn(self.workScheduler)
              .subscribe(onSuccess: { [weak self] _ in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: nil)
                  }
              }, onError: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: error)
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func processDeletionsSync(libraryId: LibraryIdentifier, since sinceVersion: Int) {
        let result = SyncDeletionsSyncAction(currentVersion: self.lastReturnedVersion, sinceVersion: sinceVersion,
                                             libraryId: libraryId, userId: self.userId,
                                             apiClient: self.apiClient, dbStorage: self.dbStorage,
                                             queue: self.workQueue, scheduler: self.workScheduler).result
        result.subscribeOn(self.workScheduler)
              .subscribe(onSuccess: { [weak self] conflicts in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishDeletionsSync(result: .success(conflicts), libraryId: libraryId)
                  }
              }, onError: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishDeletionsSync(result: .failure(error), libraryId: libraryId)
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func finishDeletionsSync(result: Result<[String], Error>, libraryId: LibraryIdentifier) {
        switch result {
        case .success://(let conflicts):
                // BETA: - no conflicts are created in beta, we prefer remote over everything local, so the conflicts
                // should be always empty now, but let's comment it just to be sure we don't unnecessarily create conflicts
//                if !conflicts.isEmpty {
//                    let actions: [Action] = conflicts.map({ .resolveConflict($0, library) })
//                    self.queue.insert(contentsOf: actions, at: 0)
//                }
            self.processNextAction()

        case .failure(let error):
            if self.handleUnchangedFailureIfNeeded(for: error, libraryId: libraryId) { return }

            switch self.syncError(from: error) {
            case .fatal(let error):
                self.abort(error: error)
            case .nonFatal(let error):
                self.nonFatalErrors.append(error)
                self.processNextAction()
            }
        }
    }

    private func processSettingsSync(for libraryId: LibraryIdentifier, since version: Int) {
        let result = SyncSettingsSyncAction(currentVersion: self.lastReturnedVersion, sinceVersion: version,
                                            libraryId: libraryId, userId: self.userId,
                                            apiClient: self.apiClient, dbStorage: self.dbStorage,
                                            queue: self.workQueue, scheduler: self.workScheduler).result
        result.subscribeOn(self.workScheduler)
              .subscribe(onSuccess: { [weak self] data in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishSettingsSync(result: .success(data), libraryId: libraryId)
                  }
              }, onError: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishSettingsSync(result: .failure(error), libraryId: libraryId)
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func finishSettingsSync(result: Result<(Bool, Int), Error>, libraryId: LibraryIdentifier) {
        switch result {
        case .success(let (hasNewSettings, version)):
            self.lastReturnedVersion = version
            if hasNewSettings {
                self.enqueue(actions: [.storeSettingsVersion(version, libraryId)], at: 0)
            } else {
                self.processNextAction()
            }

        case .failure(let error):
            if self.handleUnchangedFailureIfNeeded(for: error, libraryId: libraryId) { return }

            switch self.syncError(from: error) {
            case .fatal(let error):
                self.abort(error: error)
            case .nonFatal(let error):
                self.nonFatalErrors.append(error)
                self.processNextAction()
            }
        }
    }

    private func processSubmitUpdate(for batch: WriteBatch) {
        let result = SubmitUpdateSyncAction(parameters: batch.parameters, sinceVersion: batch.version, object: batch.object,
                                            libraryId: batch.libraryId, userId: self.userId, apiClient: self.apiClient,
                                            dbStorage: self.dbStorage, fileStorage: self.fileStorage,
                                            queue: self.workQueue, scheduler: self.workScheduler).result
        result.subscribeOn(self.workScheduler)
              .subscribe(onSuccess: { [weak self] (version, error) in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.progressHandler.reportWriteBatchSynced(size: batch.parameters.count)
                      self?.finishSubmission(error: error, newVersion: version, libraryId: batch.libraryId, object: batch.object)
                  }
              }, onError: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.progressHandler.reportWriteBatchSynced(size: batch.parameters.count)
                      self?.finishSubmission(error: error, newVersion: batch.version, libraryId: batch.libraryId, object: batch.object)
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func processUploadAttachment(for upload: AttachmentUpload) {
        let result = UploadAttachmentSyncAction(key: upload.key, file: upload.file, filename: upload.filename, md5: upload.md5,
                                                mtime: upload.mtime, libraryId: upload.libraryId, userId: self.userId, oldMd5: upload.oldMd5,
                                                apiClient: self.apiClient, dbStorage: self.dbStorage, fileStorage: self.fileStorage,
                                                queue: self.workQueue, scheduler: self.workScheduler).result
        result.subscribeOn(self.workScheduler)
              .subscribe(onSuccess: { [weak self] response, progress in
                  guard let `self` = self else { return }

                  response.subscribeOn(self.workScheduler)
                          .subscribe(onCompleted: { [weak self] in
                              self?.accessQueue.async(flags: .barrier) { [weak self] in
                                  self?.progressHandler.reportUploaded()
                                  self?.finishSubmission(error: nil, newVersion: nil, libraryId: upload.libraryId, object: .item)
                              }
                          }, onError: { [weak self] error in
                              self?.accessQueue.async(flags: .barrier) { [weak self] in
                                  self?.progressHandler.reportUploaded()
                                  self?.finishSubmission(error: error, newVersion: nil, libraryId: upload.libraryId, object: .item)
                              }
                          })
                          .disposed(by: self.disposeBag)

                  // TODO: - observe upload progress
              })
              .disposed(by: self.disposeBag)
    }

    private func processSubmitDeletion(for batch: DeleteBatch) {
        let result = SubmitDeletionSyncAction(keys: batch.keys, object: batch.object, version: batch.version, libraryId: batch.libraryId,
                                              userId: self.userId, apiClient: self.apiClient, dbStorage: self.dbStorage,
                                              queue: self.workQueue, scheduler: self.workScheduler).result
        result.subscribeOn(self.workScheduler)
              .subscribe(onSuccess: { [weak self] version in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.progressHandler.reportWriteBatchSynced(size: batch.keys.count)
                      self?.finishSubmission(error: nil, newVersion: version, libraryId: batch.libraryId, object: batch.object)
                  }
              }, onError: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.progressHandler.reportWriteBatchSynced(size: batch.keys.count)
                      self?.finishSubmission(error: error, newVersion: batch.version, libraryId: batch.libraryId, object: batch.object)
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func finishSubmission(error: Error?, newVersion: Int?, libraryId: LibraryIdentifier, object: SyncObject) {
        if let error = error {
            if self.handleUpdatePreconditionFailureIfNeeded(for: error, libraryId: libraryId) {
                return
            }

            switch self.syncError(from: error) {
            case .fatal(let error):
                self.abort(error: error)
                return
            case .nonFatal(let error):
                self.nonFatalErrors.append(error)
            }
        }

        if let version = newVersion {
            self.updateVersionInNextWriteBatch(to: version)
        }
        self.processNextAction()
    }

    private func deleteGroup(with groupId: Int) {
        let result = DeleteGroupSyncAction(groupId: groupId, dbStorage: self.dbStorage).result
        result.subscribeOn(self.workScheduler)
              .subscribe(onSuccess: { [weak self] _ in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: nil)
                  }
              }, onError: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: error)
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func markGroupAsLocalOnly(with groupId: Int) {
        let result = MarkGroupAsLocalOnlySyncAction(groupId: groupId, dbStorage: self.dbStorage).result
        result.subscribeOn(self.workScheduler)
              .subscribe(onSuccess: { [weak self] _ in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: nil)
                  }
              }, onError: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: error)
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func markChangesAsResolved(in libraryId: LibraryIdentifier) {
        let result = MarkChangesAsResolvedSyncAction(libraryId: libraryId, dbStorage: self.dbStorage).result
        result.subscribeOn(self.workScheduler)
              .subscribe(onSuccess: { [weak self] _ in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: nil)
                  }
              }, onError: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: error)
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func revertGroupData(in libraryId: LibraryIdentifier) {
        let result = RevertLibraryUpdatesSyncAction(libraryId: libraryId, dbStorage: self.dbStorage,
                                                    fileStorage: self.fileStorage, schemaController: self.schemaController,
                                                    dateParser: self.dateParser).result
        result.subscribeOn(self.workScheduler)
              .subscribe(onSuccess: { [weak self] failures in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      // TODO: - report failures?
                      self?.finishCompletableAction(error: nil)
                  }
              }, onError: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: nil)
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func finishCompletableAction(error: Error?) {
        if let error = error {
            switch self.syncError(from: error) {
            case .fatal(let error):
                self.abort(error: error)
                return
            case .nonFatal(let error):
                self.nonFatalErrors.append(error)
            }
        }

        self.processNextAction()
    }

    // MARK: - Helpers

    /// Updates a version in next `WriteBatch` or `DeleteBatch` if available. This happens because submitting a batch of changes increases the version
    /// on backend. The new version is returned by backend and needs to be used in next batch, so that it doesn't report a conflict.
    /// - parameter version: New version after submission of last batch of changes.
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

    private func nonFatalError(from error: Error) -> SyncError.NonFatal {
        if let error = error as? SyncError.NonFatal {
            return error
        }
        if let error = error as? SchemaError {
            return .schema(error)
        }
        if let error = error as? Parsing.Error {
            return .parsing(error)
        }
        return .unknown
    }

    /// Checks whether given error is fatal or nonfatal.
    /// - parameter error: Error to check.
    /// - returns: Appropriate `SyncError`.
    private func syncError(from error: Error) -> SyncError {
        if let error = error as? SyncError.Fatal {
            return .fatal(error)
        } else if let error = error as? SyncError.NonFatal {
            return .nonFatal(error)
        }

        let nsError = error as NSError

        // Check connection
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorNotConnectedToInternet {
            return .fatal(.noInternetConnection)
        }

        // Check other networking errors
        if let responseError = error as? AFResponseError {
            return self.alamoErrorRequiresAbort(responseError.error, response: responseError.response)
        }
        if let alamoError = error as? AFError {
            return self.alamoErrorRequiresAbort(alamoError, response: "No response")
        }

        // Check realm errors, every "core" error is bad. Can't create new Realm instance, can't continue with sync
        if error is Realm.Error {
            return .fatal(.dbError)
        }

        return .nonFatal(self.nonFatalError(from: error))
    }

    /// Checks whether given `AFError` is fatal and requires abort.
    /// - error: `AFError` to check.
    /// - returns: `SyncError` with appropriate error, if abort is required, `nil` otherwise.
    private func alamoErrorRequiresAbort(_ error: AFError, response: String) -> SyncError {
        switch error {
        case .responseValidationFailed(let reason):
            switch reason {
            case .unacceptableStatusCode(let code):
                return (code >= 400 && code <= 499 && code != 403) ? .fatal(.apiError(response)) : .nonFatal(.apiError(response))
            case .dataFileNil, .dataFileReadFailed, .missingContentType, .unacceptableContentType, .customValidationFailed:
                return .fatal(.apiError(response))
            }
        case .multipartEncodingFailed, .parameterEncodingFailed, .parameterEncoderFailed, .invalidURL, .createURLRequestFailed,
             .requestAdaptationFailed, .requestRetryFailed, .serverTrustEvaluationFailed, .sessionDeinitialized, .sessionInvalidated,
             .urlRequestValidationFailed, .sessionTaskFailed:
            return .fatal(.apiError(response))
        case .responseSerializationFailed, .createUploadableFailed, .downloadedFileMoveFailed, .explicitlyCancelled:
            return .nonFatal(.apiError(response))
        }
    }

    /// Handles version mismatch error. Version mismatch is handled by removing actions for current library, so that we don't get conflicts.
    /// - parameter libraryId: Identifier of current library, which is being synced.
    /// - returns: `true` if there was a mismatch error, `false` otherwise.
    private func handleVersionMismatch(for libraryId: LibraryIdentifier) {
        // If the backend received higher version in response than from previous responses, there was a change on backend and we'll probably
        // have conflicts. Abort this library and continue with sync.
        self.nonFatalErrors.append(.versionMismatch)
        self.removeAllActions(for: libraryId)
        self.processNextAction()
    }

    /// Handles precondition error, if required. Precondition error is handled by removing all actions for current library. Then downloading all
    /// remote changes from backend and then trying to submit our local changes again.
    /// - parameter error: Error to check.
    /// - parameter libraryId: Identifier of current library, which is being synced.
    /// - returns: `true` if there was a precondition error, `false` otherwise.
    private func handleUpdatePreconditionFailureIfNeeded(for error: Error, libraryId: LibraryIdentifier) -> Bool {
        guard let preconditionError = error.preconditionError else { return false }

        // Remote has newer version than local, we need to remove remaining write actions for this library from queue,
        // sync remote changes and then try to upload our local changes again, we remove existing write actions from
        // queue because they might change - for example some deletions might be overwritten by remote changes

        if self.createActionOptions == .onlyWrites {
            // We already tried this before and it didn't work, abort sync.
            self.abort(error: .preconditionErrorCantBeResolved)
            return true
        }

        switch preconditionError {
        case .objectConflict:
            self.abort(error: .uploadObjectConflict)

        case .libraryConflict:
            guard self.conflictRetries < self.conflictDelays.count else {
                self.abort(error: .cantResolveConflict)
                return true
            }

            let delay = self.conflictDelays[min(self.conflictRetries, (self.conflictDelays.count - 1))]
            let actions: [Action] = [.createLibraryActions(.specific([libraryId]), .forceDownloads),
                                     .createLibraryActions(.specific([libraryId]), .onlyWrites)]

            self.conflictRetries += 1

            self.removeAllActions(for: libraryId)
            self.enqueue(actions: actions, at: 0, delay: delay)
        }

        return true
    }

    /// Handle unchanged "error", if required. If backend returns response code 304, it is treated as error. If this error is returned,
    /// we can safely assume, that there are no further remote changes for any object (collections, items, searches, annotations) for this version.
    /// However, some objects may be out of sync (if sync interrupted previously), so other object versions need to be checked. If other object
    /// versions match current version, they can be removed from sync, otherwise they need to sync anyway.
    /// - parameter error: Error to check.
    /// - parameter libraryId: Identifier of current library, which is being synced.
    /// - returns: `true` if there was a unchanged error, `false` otherwise.
    private func handleUnchangedFailureIfNeeded(for error: Error, libraryId: LibraryIdentifier) -> Bool {
        guard case ZoteroApiError.unchanged(let lastVersion) = error else { return false }

        self.lastReturnedVersion = lastVersion

        // If current sync type is `.all` we don't want to skip anything.
        guard self.type != .all else {
            self.processNextAction()
            return true
        }

        var toDelete: [Int] = []

        for (index, action) in self.queue.enumerated() {
            guard action.libraryId == libraryId else { break }
            switch action {
            case .syncVersions(let libraryId, let object, let version, _):
                // If there are no remote changes for previous `Object`, we should check whether current `Object` has been synced up to recent version,
                // so we compare current version with last returned version.
                // Even if the current object was previously fully synced, we need to check for local unsynced objects anyway.
                self.queue[index] = .syncVersions(libraryId: libraryId, object: object, version: version, checkRemote: (version < lastVersion))
            case .syncSettings(_, let version),
                 .syncDeletions(_, let version):
                if lastVersion == version {
                    toDelete.append(index)
                }
            default: break
            }
        }

        toDelete.reversed().forEach { self.queue.remove(at: $0) }

        self.processNextAction()

        return true
    }
}

fileprivate extension SyncController.Action {
    var libraryId: LibraryIdentifier? {
        switch self {
        case .loadKeyPermissions, .createLibraryActions, .syncGroupVersions:
            return nil
        case .syncBatchesToDb(let batches):
            return batches.first?.libraryId
        case .submitWriteBatch(let batch):
            return batch.libraryId
        case .submitDeleteBatch(let batch):
            return batch.libraryId
        case .uploadAttachment(let upload):
            return upload.libraryId
        case .resolveDeletedGroup(let groupId, _),
             .resolveGroupMetadataWritePermission(let groupId, _),
             .deleteGroup(let groupId),
             .markGroupAsLocalOnly(let groupId),
             .syncGroupToDb(let groupId):
            return .group(groupId)
        case .syncVersions(let libraryId, _, _, _),
             .storeVersion(_, let libraryId, _),
             .syncDeletions(let libraryId, _),
             .syncSettings(let libraryId, _),
             .storeSettingsVersion(_, let libraryId),
             .resolveConflict(_, let libraryId),
             .markChangesAsResolved(let libraryId),
             .revertLibraryToOriginal(let libraryId),
             .createUploadActions(let libraryId):
            return libraryId
        }
    }

    var requiresConflictReceiver: Bool {
        switch self {
        case .resolveConflict, .resolveDeletedGroup, .resolveGroupMetadataWritePermission:
            return true
        case .loadKeyPermissions, .createLibraryActions, .storeSettingsVersion, .syncSettings, .syncVersions,
             .storeVersion, .submitDeleteBatch, .submitWriteBatch, .syncDeletions, .deleteGroup,
             .markChangesAsResolved, .markGroupAsLocalOnly, .revertLibraryToOriginal, .uploadAttachment,
             .createUploadActions, .syncGroupVersions, .syncGroupToDb, .syncBatchesToDb:
            return false
        }
    }

    var requiresDebugPermissionPrompt: Bool {
        switch self {
        case .submitDeleteBatch, .submitWriteBatch, .uploadAttachment:
            return true
        case .loadKeyPermissions, .createLibraryActions, .storeSettingsVersion, .syncSettings, .syncVersions,
             .storeVersion, .syncDeletions, .deleteGroup,
             .markChangesAsResolved, .markGroupAsLocalOnly, .revertLibraryToOriginal,
             .createUploadActions, .resolveConflict, .resolveDeletedGroup, .resolveGroupMetadataWritePermission, .syncGroupVersions,
             .syncGroupToDb, .syncBatchesToDb:
            return false
        }
    }

    var debugPermissionMessage: String {
        switch self {
        case .submitDeleteBatch(let batch):
            return "Delete \(batch.keys.count) \(batch.object) in \(batch.libraryId.debugName)\n\(batch.keys)"
        case .submitWriteBatch(let batch):
            return "Write \(batch.parameters.count) changes for \(batch.object) in \(batch.libraryId.debugName)\n\(batch.parameters)"
        case .uploadAttachment(let upload):
            return "Upload \(upload.filename) (\(upload.contentType)) in \(upload.libraryId.debugName)\n\(upload.file.createUrl().absoluteString)"
        case .loadKeyPermissions, .createLibraryActions, .storeSettingsVersion, .syncSettings, .syncVersions,
             .storeVersion, .syncDeletions, .deleteGroup,
             .markChangesAsResolved, .markGroupAsLocalOnly, .revertLibraryToOriginal,
             .createUploadActions, .resolveConflict, .resolveDeletedGroup, .resolveGroupMetadataWritePermission,
             .syncGroupVersions, .syncGroupToDb, .syncBatchesToDb:
            return "Unknown action"
        }
    }
}
