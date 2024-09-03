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

protocol SyncAction {
    associatedtype Result

    var result: Single<Result> { get }
}

protocol SynchronizationController: AnyObject {
    var progressObservable: PublishSubject<SyncProgress> { get }

    func start(type: SyncController.Kind, libraries: SyncController.Libraries, retryAttempt: Int)
    func set(coordinator: ConflictCoordinator?)
    func cancel()
}

final class SyncController: SynchronizationController {
    /// Type of sync
    enum Kind {
        /// Only objects which need to be synced are fetched. Either synced objects with old version or unsynced objects with expired backoff schedule.
        case normal
        /// Same as .normal, but individual backoff schedule is ignored.
        case ignoreIndividualDelays
        /// All deletions are re-applied, all versions are fetched and compared to local state of objects. Objects are re-downloaded if missing or are outdated (ignoring backoff schedule).
        /// Local synced objects which are missing remotely are marked as changed by user, so that they are re-submitted on next sync.
        case full
        /// Synchronize only collections.
        case collectionsOnly
        /// Only call the `/keys` request to check whether user is still logged in.
        case keysOnly
        /// Perform all downloads first, then try writing again
        case prioritizeDownloads
    }

    /// Specifies which libraries need to be synced.
    enum Libraries: Equatable {
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
        case onlyDownloads
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
        case createLibraryActions(Libraries, CreateLibraryActionsOptions)
        /// Loads items that need upload, spawns actions for each.
        case createUploadActions(libraryId: LibraryIdentifier, hadOtherWriteActions: Bool, canEditFiles: Bool)
        /// Starts `SyncBatchProcessor` which downloads and stores all batches.
        case syncBatchesToDb([DownloadBatch])
        /// Store new version for given library-object.
        case storeVersion(Int, LibraryIdentifier, SyncObject)
        /// Load deletions of objects in library. If an object is currently being edited by user, we need to ask for permissions or alert the user.
        case syncDeletions(LibraryIdentifier, Int)
        /// Performs deletions on objects.
        case performDeletions(
            libraryId: LibraryIdentifier,
            collections: [String],
            items: [String],
            searches: [String],
            tags: [String],
            conflictMode: PerformItemDeletionsDbRequest.ConflictResolutionMode
        )
        /// Restores remote deletions
        case restoreDeletions(libraryId: LibraryIdentifier, collections: [String], items: [String])
        /// Stores version for deletions in given library.
        case storeDeletionVersion(libraryId: LibraryIdentifier, version: Int)
        /// Synchronize settings for library.
        case syncSettings(LibraryIdentifier, Int)
        /// Submit local changes to backend.
        case submitWriteBatch(WriteBatch)
        /// Upload local attachment to backend.
        case uploadAttachment(AttachmentUpload)
        /// Submit local deletions to backend.
        case submitDeleteBatch(DeleteBatch)
        /// Handle group that was deleted remotely - (Id, Name).
        case resolveDeletedGroup(Int, String)
        /// Resolve when group had metadata editing allowed, but it was disabled and we try to submit new data.
        case resolveGroupMetadataWritePermission(groupId: Int, name: String)
        /// Resolve when group had file editing allowed, but it was disabled and we try to upload new files
        case resolveGroupFileWritePermission(groupId: Int, name: String)
        /// Revert all changes to original cached version of this group.
        case revertLibraryToOriginal(LibraryIdentifier)
        /// Revert all attachment items to original cached version of this group.
        case revertLibraryFilesToOriginal(LibraryIdentifier)
        /// Local changes couldn't be written remotely, but we want to keep them locally anyway.
        case markChangesAsResolved(LibraryIdentifier)
        /// Removes group from db.
        case deleteGroup(Int)
        /// Marks group as local only (not synced with backend).
        case markGroupAsLocalOnly(Int)
        /// Fetch group data and store to db.
        case syncGroupToDb(Int)
        /// Removes files of deleted attachment items from remote WebDAV storage.
        case performWebDavDeletions(LibraryIdentifier)
        /// Fix for #584 where background upload is processed but main app is not notified and tries to upload the same file again.
        case fixUpload(key: String, libraryId: LibraryIdentifier)
        /// Removes all actions from queue for given library identifier.
        case removeActions(libraryId: LibraryIdentifier)

        var logString: String {
            switch self {
            case .syncBatchesToDb(let batches):
                return "syncBatchesToDb(\(batches.count) batches)"

            case .performDeletions(let libraryId, let collections, let items, let searches, let tags, let ignoreConflicts):
                return "performDeletions(\(libraryId), \(collections.count) collections, \(items.count) items, \(searches.count) searches, \(tags.count) tags, \(ignoreConflicts))"

            case .restoreDeletions(let libraryId, let collections, let items):
                return "restoreDeletions(\(libraryId), \(collections.count) collections, \(items.count) items)"

            case .submitWriteBatch(let batch):
                return "submitWriteBatch(\(batch.libraryId), \(batch.object), \(batch.version), \(batch.parameters.count) objects)"

            case .submitDeleteBatch(let batch):
                return "submitDeleteBatch(\(batch.libraryId), \(batch.object), \(batch.version), \(batch.keys.count) objects)"

            case .fixUpload(let key, let libraryId):
                return "fixUpload(\(key); \(libraryId))"

            case .loadKeyPermissions,
                 .createLibraryActions,
                 .createUploadActions,
                 .syncGroupVersions,
                 .syncVersions,
                 .syncGroupToDb,
                 .storeVersion,
                 .syncDeletions,
                 .storeDeletionVersion,
                 .syncSettings,
                 .uploadAttachment,
                 .deleteGroup,
                 .markGroupAsLocalOnly,
                 .revertLibraryToOriginal,
                 .markChangesAsResolved,
                 .resolveDeletedGroup,
                 .resolveGroupMetadataWritePermission,
                 .performWebDavDeletions,
                 .resolveGroupFileWritePermission,
                 .revertLibraryFilesToOriginal,
                 .removeActions:
                return "\(self)"
            }
        }
    }

    // All access to local variables is performed on this queue.
    private let accessQueue: DispatchQueue
    // All processing of actions is performed on this queue.
    private let workQueue: DispatchQueue
    // All processing of actions is scheduled on this scheduler.
    private let workScheduler: SerialDispatchQueueScheduler
    // Controllers
    private unowned let apiClient: ApiClient
    private unowned let attachmentDownloader: AttachmentDownloader
    private unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage
    private unowned let schemaController: SchemaController
    private unowned let dateParser: DateParser
    private unowned let backgroundUploaderContext: BackgroundUploaderContext
    private unowned let webDavController: WebDavController
    // Handler for reporting sync progress to observers.
    private let progressHandler: SyncProgressHandler
    // Id of currently logged in user.
    private let userId: Int
    // Maximum number of retries that should be attempted. If limit has been reached, just report error and stop retrying.
    private let maxRetryCount: Int
    // Delay for syncing. Local objects won't try to sync again until the delay passes (based on count of retries).
    private let syncDelayIntervals: [Double]
    // Kind and Libraries are types used for new sync, if available, otherwise sync is not needed.
    let observable: PublishSubject<SyncScheduler.Sync?>

    // Type of current sync.
    private var type: Kind
    // Queue of sync actions.
    private var queue: [Action]
    // Current action in progress.
    private var processingAction: Action?
    // Sync type for libraries.
    private var libraryType: Libraries
    // Version returned by last object sync, used to check for version mismatches between object syncs
    private var lastReturnedVersion: Int?
    // Array of non-fatal errors that happened during current sync
    private var nonFatalErrors: [SyncError.NonFatal]
    // DisposeBag is a var so that the sync can be cancelled.
    private var disposeBag: DisposeBag
    // Current retry attempt. Used to report retries back to `SyncScheduler`.
    private var retryAttempt: Int
    // Access permissions for current sync.
    private var accessPermissions: AccessPermissions?
    // Used for conflict resolution when user interaction is needed.
    private var conflictCoordinator: ConflictCoordinator?
    // Used for syncing batches of objects in `.syncBatchesToDb` action
    private var batchProcessor: SyncBatchProcessor?
    // Indicates whether sync submitted any writes or deletes to Zotero backend.
    private var didEnqueueWriteActionsToZoteroBackend: Bool
    // Number of uploads that were enqueued during this sync
    private var enqueuedUploads: Int
    // Number of uploads which failed before making a HTTP request to Zotero backend. Used to detect whether sync should check remote changes after unsuccessful uploads (#381).
    private var uploadsFailedBeforeReachingZoteroBackend: Int

    private var isSyncing: Bool {
        return self.processingAction != nil || !self.queue.isEmpty
    }

    // MARK: - Testing

    var reportFinish: ((Result<([Action], [Error]), Error>) -> Void)?
    private var allActions: [Action] = []

    // MARK: - Lifecycle

    init(
        userId: Int,
        apiClient: ApiClient,
        dbStorage: DbStorage,
        fileStorage: FileStorage,
        schemaController: SchemaController,
        dateParser: DateParser,
        backgroundUploaderContext: BackgroundUploaderContext,
        webDavController: WebDavController,
        attachmentDownloader: AttachmentDownloader,
        syncDelayIntervals: [Double],
        maxRetryCount: Int
    ) {
        let accessQueue = DispatchQueue(label: "org.zotero.SyncController.accessQueue", qos: .userInteractive, attributes: .concurrent)
        let workQueue = DispatchQueue(label: "org.zotero.SyncController.workQueue", qos: .userInteractive)
        self.userId = userId
        self.accessQueue = accessQueue
        self.workQueue = workQueue
        self.workScheduler = SerialDispatchQueueScheduler(queue: workQueue, internalSerialQueueName: "org.zotero.SyncController.workScheduler")
        self.observable = PublishSubject()
        self.progressHandler = SyncProgressHandler()
        self.disposeBag = DisposeBag()
        self.queue = []
        self.nonFatalErrors = []
        self.type = .normal
        self.libraryType = .all
        self.apiClient = apiClient
        self.attachmentDownloader = attachmentDownloader
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.schemaController = schemaController
        self.dateParser = dateParser
        self.backgroundUploaderContext = backgroundUploaderContext
        self.webDavController = webDavController
        self.syncDelayIntervals = syncDelayIntervals
        self.didEnqueueWriteActionsToZoteroBackend = false
        self.enqueuedUploads = 0
        self.uploadsFailedBeforeReachingZoteroBackend = 0
        self.retryAttempt = 0
        self.maxRetryCount = maxRetryCount
    }

    // MARK: - SynchronizationController

    var progressObservable: PublishSubject<SyncProgress> {
        return self.progressHandler.observable
    }

    /// Sets coordinator for conflict resolution.
    func set(coordinator: ConflictCoordinator?) {
        self.accessQueue.async(flags: .barrier) { [weak self] in
            self?.conflictCoordinator = coordinator

            guard coordinator != nil, let action = self?.processingAction else { return }
            // ConflictReceiver was nil and we are waiting for CR action. Which means it was ignored previously and we need to restart it.
            if action.requiresConflictReceiver || (Defaults.shared.askForSyncPermission && action.requiresDebugPermissionPrompt) {
                self?.workQueue.async {
                    self?.process(action: action)
                }
            }
        }
    }

    /// Start a new sync if another sync is not already in progress (current sync is not automatically cancelled).
    /// - parameter type: Type of sync. See `Kind` documentation for more info.
    /// - parameter libraries: Specifies which libraries should be synced. See `Libraries` documentation for more info.
    /// - parameter retryAttempt: Current retry attempt count
    func start(type: Kind, libraries: Libraries, retryAttempt: Int) {
        self.accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self, !self.isSyncing else { return }

            DDLogInfo("Sync: starting")

            self.type = type
            self.libraryType = libraries
            self.retryAttempt = retryAttempt
            self.progressHandler.reportNewSync()
            self.queue.append(contentsOf: self.createInitialActions(for: libraries, syncType: type))

            self.processNextAction()
        }
    }

    /// Cancels ongoing sync.
    func cancel() {
        self.accessQueue.async(flags: .barrier) { [weak self] in
            guard let self = self, self.isSyncing else { return }

            DDLogInfo("Sync: cancelled")

            self.cleanup()
            self.report(fatalError: .cancelled)
        }
    }

    // MARK: - Controls

    /// Finishes ongoing sync.
    private func finish() {
        DDLogInfo("Sync: finished")
        if !self.nonFatalErrors.isEmpty {
            DDLogInfo("Errors: \(self.nonFatalErrors)")
        }

        // Call finishAction after clearing `reportFinish` because tests may want to re-try through this closure when testing only `SyncController`
        let finishAction = self.reportFinish
        self.reportFinish = nil
        finishAction?(.success((self.allActions, self.nonFatalErrors)))

        self.reportFinish(nonFatalErrors: self.nonFatalErrors)
        self.cleanup()
    }

    /// Aborts ongoing sync with given error.
    /// - parameter error: Error which will be reported as a reason for this abort.
    private func abort(error: SyncError.Fatal) {
        DDLogInfo("Sync: aborted")
        DDLogInfo("Error: \(error)")

        // Call finishAction after clearing `reportFinish` because tests may want to re-try through this closure when testing only `SyncController`
        let finishAction = self.reportFinish
        self.reportFinish = nil
        finishAction?(.failure(error))

        self.report(fatalError: error)
        self.cleanup()
    }

    /// Cleans up helper variables for current sync.
    private func cleanup() {
        DDLogInfo("Sync: cleanup")
        self.processingAction = nil
        self.queue = []
        self.nonFatalErrors = []
        self.type = .normal
        self.lastReturnedVersion = nil
        self.disposeBag = DisposeBag()
        self.accessPermissions = nil
        self.batchProcessor = nil
        self.libraryType = .all
        self.didEnqueueWriteActionsToZoteroBackend = false
        self.enqueuedUploads = 0
        self.uploadsFailedBeforeReachingZoteroBackend = 0
        self.retryAttempt = 0
    }

    // MARK: - Error handling

    /// Reports fatal error. Fatal error stops the sync and aborts it. Enqueues a new sync if needed.
    /// - parameter fatalError: Error to be reported.
    private func report(fatalError: SyncError.Fatal) {
        if let sync = self.requiresRetry(fatalError: fatalError), self.retryAttempt < self.maxRetryCount {
            // Fatal error should be re-tried, don't report it yet.
            self.observable.on(.next(sync))
            return
        }

        // Fatal error not retried, report and confirm finished sync.
        self.progressHandler.reportAbort(with: fatalError)
        self.observable.on(.next(nil))
    }

    private func requiresRetry(fatalError: SyncError.Fatal) -> SyncScheduler.Sync? {
        switch fatalError {
        case .uploadObjectConflict:
            return SyncScheduler.Sync(type: .full, libraries: .all, retryAttempt: (self.retryAttempt + 1), retryOnce: true)

        case .cantSubmitAttachmentItem:
            return SyncScheduler.Sync(type: self.type, libraries: self.libraryType, retryAttempt: (self.retryAttempt + 1), retryOnce: false)

        default:
            return nil
        }
    }

    /// Reports non-fatal errors. These happened during sync, but didn't need to stop it. Enqueues a new sync if needed.
    private func reportFinish(nonFatalErrors errors: [SyncError.NonFatal]) {
        guard let (sync, remainingErrors) = self.requireRetry(nonFatalErrors: errors), self.retryAttempt < self.maxRetryCount else {
            // Don't try to retry any more. Report all errors.
            self.progressHandler.reportFinish(with: errors)
            self.observable.on(.next(nil))
            return
        }

        // Retry libraries with errors that can be fixed on next sync. Report remaining errors.
        self.progressHandler.reportFinish(with: remainingErrors)
        self.observable.on(.next(sync))
    }

    private func requireRetry(nonFatalErrors errors: [SyncError.NonFatal]) -> (SyncScheduler.Sync, [SyncError.NonFatal])? {
        // Find libraries which reported retry-able errors.
        var retryLibraries: [LibraryIdentifier] = []
        var reportErrors: [SyncError.NonFatal] = []
        var retryOnce = false
        var type = self.type

        for error in errors {
            switch error {
            case .versionMismatch(let libraryId), .preconditionFailed(let libraryId):
                // Retry on conflict (either library version changed during fetching remote changes or submission received 412).
                if !retryLibraries.contains(libraryId) {
                    retryLibraries.append(libraryId)
                }
                retryOnce = true
                type = .prioritizeDownloads

            case .annotationDidSplit(_, _, let libraryId):
                // Retry so that split annotations are synced.
                if !retryLibraries.contains(libraryId) {
                    retryLibraries.append(libraryId)
                }

            case .unknown,
                 .schema,
                 .parsing,
                 .apiError,
                 .unchanged,
                 .quotaLimit,
                 .attachmentMissing,
                 .insufficientSpace,
                 .webDavDeletion,
                 .webDavDeletionFailed,
                 .webDavVerification,
                 .webDavDownload,
                 .webDavUpload:
                reportErrors.append(error)
            }
        }

        if retryLibraries.isEmpty {
            return nil
        }

        return (SyncScheduler.Sync(type: type, libraries: .specific(retryLibraries), retryAttempt: (self.retryAttempt + 1), retryOnce: retryOnce), reportErrors)
    }

    // MARK: - Queue management

    /// Enqueues new actions and starts processing next action.
    /// - parameter actions: Array of actions to be added.
    /// - parameter index: Index in array where actions should be added. If nil, they will be appended.
    private func enqueue(actions: [Action], at index: Int? = nil) {
        if !actions.isEmpty {
            if let index = index {
                self.queue.insert(contentsOf: actions, at: index)
            } else {
                self.queue.append(contentsOf: actions)
            }
        }

        self.processNextAction()
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
            DDLogInfo("Sync: library changed, clear version")
            self.lastReturnedVersion = nil
        }

        self.processingAction = action

        if action.requiresConflictReceiver && self.conflictCoordinator == nil {
            DDLogInfo("Sync: waiting for conflict coordinator")
            return
        }

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
        DDLogInfo("Sync: \(action.logString)")

        switch action {
        case .loadKeyPermissions:
            self.processKeyCheckAction()

        case .createLibraryActions(let libraries, let options):
            self.processCreateLibraryActions(for: libraries, options: options)

        case .createUploadActions(let libraryId, let hadOtherWriteActions, let canWriteFiles):
            self.processCreateUploadActions(for: libraryId, hadOtherWriteActions: hadOtherWriteActions, canWriteFiles: canWriteFiles)

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
            self.loadRemoteDeletions(libraryId: libraryId, since: version)

        case .performDeletions(let libraryId, let collections, let items, let searches, let tags, let conflictMode):
            self.performDeletions(libraryId: libraryId, collections: collections, items: items, searches: searches, tags: tags, conflictMode: conflictMode)

        case .restoreDeletions(let libraryId, let collections, let items):
            self.restoreDeletions(libraryId: libraryId, collections: collections, items: items)

        case .storeDeletionVersion(let libraryId, let version):
            self.processStoreVersion(libraryId: libraryId, type: .deletions, version: version)

        case .syncSettings(let libraryId, let version):
            self.progressHandler.reportLibrarySync(for: libraryId)
            self.processSettingsSync(for: libraryId, since: version)

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

        case .resolveDeletedGroup(let groupId, let name):
            self.resolve(conflict: .groupRemoved(groupId: groupId, name: name))

        case .resolveGroupMetadataWritePermission(let groupId, let name):
            self.resolve(conflict: .groupMetadataWriteDenied(groupId: groupId, name: name))

        case .resolveGroupFileWritePermission(let groupId, let name):
            self.resolve(conflict: .groupFileWriteDenied(groupId: groupId, name: name))

        case .performWebDavDeletions(let libraryId):
            self.performWebDavDeletions(libraryId: libraryId)

        case .fixUpload(let key, let libraryId):
            self.processUploadFix(forKey: key, libraryId: libraryId)

        case .removeActions(let libraryId):
            self.removeAllActions(for: libraryId)

        case .revertLibraryFilesToOriginal(let libraryId):
            self.revertGroupFiles(in: libraryId)
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
                guard let self = self else { return }
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

        case .markGroupAsLocalOnly(let id):
            return [.markGroupAsLocalOnly(id)]

        case .revertGroupChanges(let id):
            return [.revertLibraryToOriginal(id)]

        case .skipGroup(let libraryId):
            return [.removeActions(libraryId: libraryId)]

        case .revertGroupFiles(let libraryId):
            return [.revertLibraryFilesToOriginal(libraryId)]

        case .remoteDeletionOfActiveObject(let libraryId, let toDeleteCollections, let toRestoreCollections, let toDeleteItems, let toRestoreItems, let searches, let tags):
            var actions: [Action] = []
            if !toDeleteCollections.isEmpty || !toDeleteItems.isEmpty || !searches.isEmpty || !tags.isEmpty {
                actions.append(.performDeletions(libraryId: libraryId, collections: toDeleteCollections, items: toDeleteItems, searches: searches, tags: tags, conflictMode: .resolveConflicts))
            }
            if !toRestoreCollections.isEmpty || !toRestoreItems.isEmpty {
                actions.append(.restoreDeletions(libraryId: libraryId, collections: toRestoreCollections, items: toRestoreItems))
            }
            return actions

        case .remoteDeletionOfChangedItem(let libraryId, let toDelete, let toRestore):
            var actions: [Action] = []
            if !toDelete.isEmpty {
                actions.append(.performDeletions(libraryId: libraryId, collections: [], items: toDelete, searches: [], tags: [], conflictMode: .deleteConflicts))
            }
            if !toRestore.isEmpty {
                actions.append(.restoreDeletions(libraryId: libraryId, collections: [], items: toRestore))
            }
            return actions
        }
    }

    /// Create initial actions for a sync. All sync will have key/permission sync. Then if a group needs to be synced
    /// (so libraries are either .all, or .specific contains a group id), then sync group metadata. If only my library is synced, after
    /// key sync jump straight to .createLibraryActions.
    /// - parameter libraries: Specifies which libraries need to sync.
    /// - returns: Initial ations for a new sync.
    private func createInitialActions(for libraries: Libraries, syncType: Kind) -> [SyncController.Action] {
        if case .keysOnly = syncType {
            return [.loadKeyPermissions]
        }

        switch libraries {
        case .all:
            return [.loadKeyPermissions, .syncGroupVersions]

        case .specific(let identifiers):
            // If there is a group to be synced, sync group metadata as well
            if identifiers.contains(where: { $0.isGroupLibrary }) {
                return [.loadKeyPermissions, .syncGroupVersions]
            }
            // Otherwise skip group metadata sync
            let options = self.libraryActionsOptions(from: syncType)
            return [.loadKeyPermissions] + options.map({ .createLibraryActions(libraries, $0) })
        }
    }

    private func libraryActionsOptions(from syncType: Kind) -> [CreateLibraryActionsOptions] {
        switch syncType {
        case .full, .collectionsOnly:
            return [.onlyDownloads]

        case .ignoreIndividualDelays, .normal, .keysOnly:
            return [.automatic]

        case .prioritizeDownloads:
            return [.onlyDownloads, .onlyWrites]
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
        result.subscribe(on: self.workScheduler)
              .flatMap { response -> Single<(AccessPermissions, String, String)> in
                  let permissions = AccessPermissions(user: response.user,
                                                      groupDefault: response.defaultGroup,
                                                      groups: response.groups)

                  if let group = permissions.groupDefault, !group.library || !group.write {
                      return Single.error(SyncError.Fatal.missingGroupPermissions)
                  }
                  return Single.just((permissions, response.username, response.displayName))
              }
              .subscribe(onSuccess: { [weak self] permissions, username, displayName in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      Defaults.shared.username = username
                      Defaults.shared.displayName = displayName
                      self?.accessPermissions = permissions
                      self?.processNextAction()
                  }
              }, onFailure: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.abort(error: (self?.syncError(from: error, data: .from(libraryId: .custom(.myLibrary))).fatal ?? .permissionLoadingFailed))
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func processCreateLibraryActions(for libraries: Libraries, options: CreateLibraryActionsOptions) {
        let result = LoadLibraryDataSyncAction(
            type: libraries,
            fetchUpdates: (options != .onlyDownloads),
            loadVersions: (self.type != .full),
            webDavEnabled: self.webDavController.sessionStorage.isEnabled,
            dbStorage: self.dbStorage,
            queue: self.workQueue
        ).result
        result.subscribe(on: self.workScheduler)
              .subscribe(onSuccess: { [weak self] data in
                  self?.finishCreateLibraryActions(with: .success((data, options)))
              }, onFailure: { [weak self] error in
                  self?.finishCreateLibraryActions(with: .failure(error))
              })
              .disposed(by: self.disposeBag)
    }

    private func finishCreateLibraryActions(with result: Result<([LibraryData], CreateLibraryActionsOptions), Error>) {
        switch result {
        case .failure(let error):
            self.accessQueue.async(flags: .barrier) { [weak self] in
                self?.abort(error: self?.syncError(from: error, data: .from(libraryId: .custom(.myLibrary))).fatal ?? .allLibrariesFetchFailed)
            }

        case .success((let data, let options)):
            var libraryNames: [LibraryIdentifier: String]?

            // Report library names in case of `.automatic` options, which are usual for regular sync or in case of full sync (which uses `.forceDownloads`)
            if options == .automatic || self.type == .full {
                var nameDictionary: [LibraryIdentifier: String] = [:]
                for libraryData in data {
                    nameDictionary[libraryData.identifier] = libraryData.name
                }
                libraryNames = nameDictionary
            }
            let (actions, queueIndex, writeCount) = self.createLibraryActions(for: data, creationOptions: options)

            self.accessQueue.async(flags: .barrier) { [weak self] in
                // If `options != .automatic`, this is most likely a 412, or other kind of retry action, so we definitely already had write actions before. We don't need to check for this anymore.
                self?.didEnqueueWriteActionsToZoteroBackend = options != .automatic || writeCount > 0
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
        var actions: [Action] = []

        for libraryData in data {
            let (_actions, _writeCount) = self.createLibraryActions(for: libraryData, creationOptions: creationOptions)
            writeCount += _writeCount
            actions.append(contentsOf: _actions)
        }

        // Forced downloads or writes are pushed to the beginning of the queue, because only currently running action
        // can force downloads or writes
        let index: Int? = creationOptions == .automatic ? nil : 0
        return (actions, index, writeCount)
    }

    private func createLibraryActions(for libraryData: LibraryData, creationOptions: CreateLibraryActionsOptions) -> ([Action], Int) {
        switch creationOptions {
        case .onlyDownloads:
            let actions = self.createDownloadActions(for: libraryData.identifier, versions: libraryData.versions)
            return (actions, 0)

        case .onlyWrites:
            var actions: [Action] = []
            var writeCount = 0

            if !libraryData.updates.isEmpty || !libraryData.deletions.isEmpty || libraryData.hasUpload {
                let (_actions, _writeCount) = self.createLibraryWriteActions(for: libraryData)
                actions = _actions
                writeCount = _writeCount
            }

            // If there are pending WebDAV deletions, always try to remove remaining files.
            if libraryData.hasWebDavDeletions {
                actions.append(.performWebDavDeletions(libraryData.identifier))
            }

            return (actions, writeCount)

        case .automatic:
            var actions: [Action] = []
            var writeCount = 0

            if !libraryData.updates.isEmpty || !libraryData.deletions.isEmpty || libraryData.hasUpload {
                let (_actions, _writeCount) = self.createLibraryWriteActions(for: libraryData)
                actions = _actions
                writeCount = _writeCount
            } else {
                actions = self.createDownloadActions(for: libraryData.identifier, versions: libraryData.versions)
            }

            // If there are pending WebDAV deletions, always try to remove remaining files.
            if libraryData.hasWebDavDeletions {
                actions.append(.performWebDavDeletions(libraryData.identifier))
            }

            return (actions, writeCount)
        }
    }

    private func createLibraryWriteActions(for libraryData: LibraryData) -> ([Action], Int) {
        switch libraryData.identifier {
        case .custom:
            // We can always write to custom libraries
            let actions = self.createUpdateActions(updates: libraryData.updates, deletions: libraryData.deletions, libraryData: libraryData)
            return (actions, actions.count - 1)

        case .group(let groupId):
            // We need to check permissions for group
            if !libraryData.canEditMetadata {
                return ([.resolveGroupMetadataWritePermission(groupId: groupId, name: libraryData.name)], 0)
            }
            let actions = self.createUpdateActions(updates: libraryData.updates, deletions: libraryData.deletions, libraryData: libraryData)
            return (actions, actions.count - 1)
        }
    }

    private func createUpdateActions(updates: [WriteBatch], deletions: [DeleteBatch], libraryData: LibraryData) -> [Action] {
        var actions: [Action] = []
        if !updates.isEmpty {
            actions.append(contentsOf: updates.map({ .submitWriteBatch($0) }))
        }
        if !deletions.isEmpty {
            actions.append(contentsOf: deletions.map({ .submitDeleteBatch($0) }))
        }
        actions.append(.createUploadActions(libraryId: libraryData.identifier, hadOtherWriteActions: (!updates.isEmpty || !deletions.isEmpty), canEditFiles: libraryData.canEditFiles))
        return actions
    }

    private func createDownloadActions(for libraryId: LibraryIdentifier, versions: Versions) -> [Action] {
        switch self.type {
        case .keysOnly:
            return []

        case .collectionsOnly:
            return [.syncVersions(libraryId: libraryId, object: .collection, version: versions.collections, checkRemote: true)]

        case .full:
            return [.syncSettings(libraryId, versions.settings),
                    .syncDeletions(libraryId, versions.deletions),
                    .storeDeletionVersion(libraryId: libraryId, version: versions.deletions),
                    .syncVersions(libraryId: libraryId, object: .collection, version: versions.collections, checkRemote: true),
                    .syncVersions(libraryId: libraryId, object: .search, version: versions.searches, checkRemote: true),
                    .syncVersions(libraryId: libraryId, object: .item, version: versions.items, checkRemote: true),
                    .syncVersions(libraryId: libraryId, object: .trash, version: versions.trash, checkRemote: true)]

        case .ignoreIndividualDelays, .normal, .prioritizeDownloads:
            return [.syncSettings(libraryId, versions.settings),
                    .syncVersions(libraryId: libraryId, object: .collection, version: versions.collections, checkRemote: true),
                    .syncVersions(libraryId: libraryId, object: .search, version: versions.searches, checkRemote: true),
                    .syncVersions(libraryId: libraryId, object: .item, version: versions.items, checkRemote: true),
                    .syncVersions(libraryId: libraryId, object: .trash, version: versions.trash, checkRemote: true),
                    .syncDeletions(libraryId, versions.deletions),
                    .storeDeletionVersion(libraryId: libraryId, version: versions.deletions)]
        }
    }

    private func processCreateUploadActions(for libraryId: LibraryIdentifier, hadOtherWriteActions: Bool, canWriteFiles: Bool) {
        let result = LoadUploadDataSyncAction(
            libraryId: libraryId,
            backgroundUploaderContext: self.backgroundUploaderContext,
            dbStorage: self.dbStorage,
            fileStorage: self.fileStorage,
            queue: self.workQueue
        ).result
        result.subscribe(on: self.workScheduler)
              .subscribe(onSuccess: { [weak self] uploads in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.process(uploads: uploads, hadOtherWriteActions: hadOtherWriteActions, libraryId: libraryId, canWriteFiles: canWriteFiles)
                  }
              }, onFailure: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.enqueuedUploads = 0
                      self?.uploadsFailedBeforeReachingZoteroBackend = 0
                      self?.finishCompletableAction(error: (error, .from(libraryId: libraryId)))
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func process(uploads: [AttachmentUpload], hadOtherWriteActions: Bool, libraryId: LibraryIdentifier, canWriteFiles: Bool) {
        if uploads.isEmpty {
            // If no uploads were loaded (probably because there are ongoing background uploads) and there were other write actions performed, continue with next actions.
            if hadOtherWriteActions {
                self.processNextAction()
                return
            }

            // If there were no other actions performed, we need to check for remote changes for this library.
            self.queue.insert(.createLibraryActions(.specific([libraryId]), .onlyDownloads), at: 0)
            self.processNextAction()
            return
        }

        if !canWriteFiles {
            switch libraryId {
            case .group(let groupId):
                let name = (try? self.dbStorage.perform(request: ReadGroupDbRequest(identifier: groupId), on: self.accessQueue))?.name ?? ""
                self.enqueue(actions: [.resolveGroupFileWritePermission(groupId: groupId, name: name)], at: 0)

            // Does not happen for custom library
            case .custom: break
            }
            return
        }

        self.progressHandler.reportUpload(count: uploads.count)
        self.enqueuedUploads = uploads.count
        self.uploadsFailedBeforeReachingZoteroBackend = 0
        self.enqueue(actions: uploads.map({ .uploadAttachment($0) }), at: 0)
    }

    private func processSyncGroupVersions() {
        let result = SyncGroupVersionsSyncAction(userId: self.userId, apiClient: self.apiClient, dbStorage: self.dbStorage, queue: self.workQueue, scheduler: self.workScheduler).result
        result.subscribe(on: self.workScheduler)
              .subscribe(onSuccess: { [weak self] toUpdate, toRemove in
                  guard let self = self else { return }
                  let actions = self.createGroupActions(updateIds: toUpdate, deleteGroups: toRemove, syncType: self.type)
                  self.accessQueue.async(flags: .barrier) { [weak self] in
                    self?.finishSyncGroupVersions(actions: actions, updateCount: toUpdate.count)
                  }
              }, onFailure: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.abort(error: self?.syncError(from: error, data: .from(libraryId: .custom(.myLibrary))).fatal ?? .groupSyncFailed)
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func finishSyncGroupVersions(actions: [Action], updateCount: Int) {
        self.progressHandler.reportGroupCount(count: updateCount)
        self.enqueue(actions: actions, at: 0)
    }

    private func createGroupActions(updateIds: [Int], deleteGroups: [(Int, String)], syncType: Kind) -> [Action] {
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
        let options = self.libraryActionsOptions(from: syncType)
        actions.append(contentsOf: options.map({ .createLibraryActions(self.libraryType, $0) }))
        return actions
    }

    private func processSyncVersions(libraryId: LibraryIdentifier, object: SyncObject, since version: Int, checkRemote: Bool) {
        let lastVersion = self.lastReturnedVersion
        let result = SyncVersionsSyncAction(
            object: object,
            sinceVersion: version,
            currentVersion: lastVersion,
            syncType: self.type,
            libraryId: libraryId,
            userId: self.userId,
            syncDelayIntervals: self.syncDelayIntervals,
            checkRemote: checkRemote,
            apiClient: self.apiClient,
            dbStorage: self.dbStorage,
            queue: self.workQueue,
            scheduler: self.workScheduler
        ).result
        result.subscribe(on: self.workScheduler)
              .subscribe(onSuccess: { [weak self] newVersion, toUpdate in
                  guard let self = self else { return }
                  let versionDidChange = version != lastVersion
                  let actions = self.createBatchedObjectActions(for: libraryId, object: object, from: toUpdate, version: newVersion, shouldStoreVersion: versionDidChange, syncType: self.type)
                  self.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishSyncVersions(actions: actions, updateCount: toUpdate.count, object: object, libraryId: libraryId)
                  }
              }, onFailure: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishFailedSyncVersions(libraryId: libraryId, object: object, error: error, version: version)
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func finishSyncVersions(actions: [Action], updateCount: Int, object: SyncObject, libraryId: LibraryIdentifier) {
        self.progressHandler.reportDownloadCount(for: object, count: updateCount, in: libraryId)
        self.enqueue(actions: actions, at: 0)
    }

    private func createBatchedObjectActions(for libraryId: LibraryIdentifier, object: SyncObject, from keys: [String], version: Int, shouldStoreVersion: Bool, syncType: Kind) -> [Action] {
        let batches = self.createBatchObjects(for: keys, libraryId: libraryId, object: object, version: version)

        guard !batches.isEmpty else {
            if shouldStoreVersion {
                return [.storeVersion(version, libraryId, object)]
            } else {
                return []
            }
        }

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

    private func finishFailedSyncVersions(libraryId: LibraryIdentifier, object: SyncObject, error: Error, version: Int) {
        switch self.syncError(from: error, data: .from(libraryId: libraryId)) {
        case .fatal(let error):
            self.abort(error: error)

        case .nonFatal(let error):
            self.handleNonFatal(error: error, libraryId: libraryId, version: version)
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

        self.batchProcessor = SyncBatchProcessor(
            batches: batches,
            userId: self.userId,
            apiClient: self.apiClient,
            dbStorage: self.dbStorage,
            fileStorage: self.fileStorage,
            schemaController: self.schemaController,
            dateParser: self.dateParser,
            progress: { [weak self] processed in
                self?.accessQueue.async(flags: .barrier) {
                    self?.progressHandler.reportDownloadBatchSynced(size: processed, for: object, in: libraryId)
                }
            },
            completion: { [weak self] result in
                self?.accessQueue.async(flags: .barrier) {
                    self?.batchProcessor = nil
                    let keys: [String] = batches.reduce([]) { $0 + $1.keys }
                    self?.finishBatchesSyncAction(for: libraryId, object: object, result: result, keys: keys)
                }
            })
        self.batchProcessor?.start()
    }

    private func finishBatchesSyncAction(for libraryId: LibraryIdentifier, object: SyncObject, result: Swift.Result<SyncBatchResponse, Error>, keys: [String]) {
        switch result {
        case .success((let failedKeys, let parseErrors, _))://let itemConflicts)):
            let nonFatalErrors = parseErrors.map({
                self.syncError(from: $0, data: .from(syncObject: object, keys: failedKeys, libraryId: libraryId)).nonFatal ??
                .unknown(message: $0.localizedDescription, data: .from(syncObject: object, keys: failedKeys, libraryId: libraryId))
            })
            self.nonFatalErrors.append(contentsOf: nonFatalErrors)

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
                DDLogInfo("Sync: batch conflicts - \(conflicts)")
            }
            if failedKeys.isEmpty {
                self.processNextAction()
            } else {
                self.workQueue.async { [weak self] in
                    self?.markForResync(keys: failedKeys, libraryId: libraryId, object: object)
                }
            }

        case .failure(let error):
            DDLogError("Sync: batch failed - \(error)")

            switch self.syncError(from: error, data: .from(libraryId: libraryId)) {
            case .fatal(let error):
                self.abort(error: error)

            case .nonFatal(let error):
                self.handleNonFatal(error: error, libraryId: libraryId, version: nil) { [weak self] in
                    self?.markForResync(keys: keys, libraryId: libraryId, object: object)
                    return false
                }
            }
        }
    }

    private func processGroupSync(groupId: Int) {
        let action = FetchAndStoreGroupSyncAction(identifier: groupId, userId: self.userId, apiClient: self.apiClient, dbStorage: self.dbStorage, queue: self.workQueue, scheduler: self.workScheduler)
        action.result
              .subscribe(on: self.workScheduler)
              .subscribe(onSuccess: { [weak self] _ in
                  self?.finishGroupSyncAction(for: groupId, error: nil)
              }, onFailure: { [weak self] error in
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

        DDLogError("Sync: group failed - \(error)")

        switch self.syncError(from: error, data: .from(libraryId: .group(identifier))) {
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
        let result = StoreVersionSyncAction(version: version, type: type, libraryId: libraryId, dbStorage: self.dbStorage, queue: self.workQueue).result
        result.subscribe(on: self.workScheduler)
              .subscribe(onSuccess: { [weak self] _ in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: nil)
                  }
              }, onFailure: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: (error, .from(libraryId: libraryId)))
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func markGroupForResync(identifier: Int) {
        let result = MarkGroupForResyncSyncAction(identifier: identifier, dbStorage: self.dbStorage, queue: self.workQueue).result
        result.subscribe(on: self.workScheduler)
              .subscribe(onSuccess: { [weak self] _ in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: nil)
                  }
              }, onFailure: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: (error, .from(libraryId: .group(identifier))))
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func markForResync(keys: [String], libraryId: LibraryIdentifier, object: SyncObject) {
        let result = MarkForResyncSyncAction(keys: keys, object: object, libraryId: libraryId, dbStorage: self.dbStorage, queue: self.workQueue).result
        result.subscribe(on: self.workScheduler)
              .subscribe(onSuccess: { [weak self] _ in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: nil)
                  }
              }, onFailure: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: (error, .from(syncObject: object, keys: keys, libraryId: libraryId)))
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func loadRemoteDeletions(libraryId: LibraryIdentifier, since sinceVersion: Int) {
        let result = LoadDeletionsSyncAction(
            currentVersion: self.lastReturnedVersion,
            sinceVersion: sinceVersion,
            libraryId: libraryId,
            userId: self.userId,
            apiClient: self.apiClient,
            queue: self.workQueue,
            scheduler: self.workScheduler
        ).result
        result.subscribe(on: self.workScheduler)
              .subscribe(onSuccess: { [weak self] collections, items, searches, tags, version in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.loadedRemoteDeletions(collections: collections, items: items, searches: searches, tags: tags, version: version, libraryId: libraryId)
                  }
              }, onFailure: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishDeletionsSync(result: .failure(error), items: nil, libraryId: libraryId, version: sinceVersion)
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func loadedRemoteDeletions(collections: [String], items: [String], searches: [String], tags: [String], version: Int, libraryId: LibraryIdentifier) {
        self.updateDeletionVersion(for: libraryId, to: version)

        switch self.type {
        case .full:
            // During full sync always restore conflicting objects (object was removed remotely, but edited locally).
            self.workQueue.async { [weak self] in
                self?.performDeletions(libraryId: libraryId, collections: collections, items: items, searches: searches, tags: tags, conflictMode: .restoreConflicts)
            }

        case .collectionsOnly, .ignoreIndividualDelays, .normal, .keysOnly, .prioritizeDownloads:
            // Find conflicting objects and perform related actions.
            self.resolve(conflict: .objectsRemovedRemotely(libraryId: libraryId, collections: collections, items: items, searches: searches, tags: tags))
        }
    }

    private func performDeletions(
        libraryId: LibraryIdentifier,
        collections: [String],
        items: [String],
        searches: [String],
        tags: [String],
        conflictMode: PerformItemDeletionsDbRequest.ConflictResolutionMode
    ) {
        let action = PerformDeletionsSyncAction(
            libraryId: libraryId,
            collections: collections,
            items: items,
            searches: searches,
            tags: tags,
            conflictMode: conflictMode,
            dbStorage: self.dbStorage,
            queue: self.workQueue
        )
        action.result.subscribe(on: self.workScheduler)
                     .subscribe(onSuccess: { [weak self] conflicts in
                         self?.accessQueue.async(flags: .barrier) { [weak self] in
                             self?.finishDeletionsSync(result: .success(conflicts), items: items, libraryId: libraryId)
                         }
                     }, onFailure: { [weak self] error in
                         self?.accessQueue.async(flags: .barrier) { [weak self] in
                             self?.finishDeletionsSync(result: .failure(error), items: items, libraryId: libraryId)
                         }
                     })
                     .disposed(by: self.disposeBag)
    }

    private func finishDeletionsSync(result: Result<[(String, String)], Error>, items: [String]?, libraryId: LibraryIdentifier, version: Int? = nil) {
        switch result {
        case .success(let conflicts):
            if !conflicts.isEmpty {
                self.resolve(conflict: .removedItemsHaveLocalChanges(keys: conflicts, libraryId: libraryId))
            } else {
                self.processNextAction()
            }

        case .failure(let error):
            let data = items.flatMap { SyncError.ErrorData.from(syncObject: (!$0.isEmpty ? .item : .collection), keys: $0, libraryId: libraryId) } ?? SyncError.ErrorData.from(libraryId: libraryId)
            switch self.syncError(from: error, data: data) {
            case .fatal(let error):
                self.abort(error: error)

            case .nonFatal(let error):
                self.handleNonFatal(error: error, libraryId: libraryId, version: version)
            }
        }
    }

    private func restoreDeletions(libraryId: LibraryIdentifier, collections: [String], items: [String]) {
        let result = RestoreDeletionsSyncAction(libraryId: libraryId, collections: collections, items: items, dbStorage: self.dbStorage, queue: self.workQueue).result
        result.subscribe(on: self.workScheduler)
              .subscribe(onSuccess: { [weak self] _ in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: nil)
                  }
              }, onFailure: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: (error, .init(itemKeys: items, libraryId: libraryId)))
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func processSettingsSync(for libraryId: LibraryIdentifier, since version: Int) {
        let result = SyncSettingsSyncAction(
            currentVersion: self.lastReturnedVersion,
            sinceVersion: version,
            libraryId: libraryId,
            userId: self.userId,
            apiClient: self.apiClient,
            dbStorage: self.dbStorage,
            queue: self.workQueue,
            scheduler: self.workScheduler
        ).result
        result.subscribe(on: self.workScheduler)
              .subscribe(onSuccess: { [weak self] data in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishSettingsSync(result: .success(data), libraryId: libraryId, version: version)
                  }
              }, onFailure: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishSettingsSync(result: .failure(error), libraryId: libraryId, version: version)
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func finishSettingsSync(result: Result<(Bool, Int), Error>, libraryId: LibraryIdentifier, version: Int) {
        switch result {
        case .success(let (hasNewSettings, version)):
            DDLogInfo("Sync: store version - \(version)")
            self.lastReturnedVersion = version
            if hasNewSettings {
                self.enqueue(actions: [.storeVersion(version, libraryId, .settings)], at: 0)
            } else {
                self.processNextAction()
            }

        case .failure(let error):
            switch self.syncError(from: error, data: .from(libraryId: libraryId)) {
            case .fatal(let error):
                self.abort(error: error)

            case .nonFatal(let error):
                self.handleNonFatal(error: error, libraryId: libraryId, version: version)
            }
        }
    }

    private func processSubmitUpdate(for batch: WriteBatch) {
        let result = SubmitUpdateSyncAction(
            parameters: batch.parameters,
            changeUuids: batch.changeUuids,
            sinceVersion: batch.version,
            object: batch.object,
            libraryId: batch.libraryId,
            userId: self.userId,
            updateLibraryVersion: true,
            apiClient: self.apiClient,
            dbStorage: self.dbStorage,
            fileStorage: self.fileStorage,
            schemaController: self.schemaController,
            dateParser: self.dateParser,
            queue: self.workQueue,
            scheduler: self.workScheduler
        ).result
        result.subscribe(on: self.workScheduler)
              .subscribe(onSuccess: { [weak self] version, error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.progressHandler.reportWriteBatchSynced(size: batch.parameters.count)
                      self?.finishSubmission(error: error, newVersion: version, keys: batch.parameters.compactMap({ $0["key"] as? String }), libraryId: batch.libraryId, object: batch.object)
                  }
              }, onFailure: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.progressHandler.reportWriteBatchSynced(size: batch.parameters.count)
                      self?.finishSubmission(error: error, newVersion: batch.version, keys: batch.parameters.compactMap({ $0["key"] as? String }), libraryId: batch.libraryId, object: batch.object)
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func processUploadAttachment(for upload: AttachmentUpload) {
        let action = UploadAttachmentSyncAction(
            key: upload.key,
            file: upload.file,
            filename: upload.filename,
            md5: upload.md5,
            mtime: upload.mtime,
            libraryId: upload.libraryId,
            userId: self.userId,
            oldMd5: upload.oldMd5,
            apiClient: self.apiClient,
            dbStorage: self.dbStorage,
            fileStorage: self.fileStorage,
            webDavController: self.webDavController,
            schemaController: self.schemaController,
            dateParser: self.dateParser,
            queue: self.workQueue,
            scheduler: self.workScheduler,
            disposeBag: self.disposeBag
        )
        action.result
              .subscribe(on: self.workScheduler)
              .subscribe(with: self, onSuccess: { `self`, _ in
                  self.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.progressHandler.reportUploaded()
                      self?.finishSubmission(error: nil, newVersion: nil, keys: [upload.key], libraryId: upload.libraryId, object: .item)
                  }
              }, onFailure: { `self`, error in
                  self.accessQueue.async(flags: .barrier) { [weak self] in
                      guard let self else { return }
                      self.progressHandler.reportUploaded()
                      self.finishSubmission(
                        error: error,
                        newVersion: nil,
                        keys: [upload.key],
                        libraryId: upload.libraryId,
                        object: .item,
                        failedBeforeReachingApi: action.failedBeforeZoteroApiRequest
                      )
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func processUploadFix(forKey key: String, libraryId: LibraryIdentifier) {
        let action = UploadFixSyncAction(
            key: key,
            libraryId: libraryId,
            userId: self.userId,
            attachmentDownloader: self.attachmentDownloader,
            fileStorage: self.fileStorage,
            dbStorage: self.dbStorage,
            queue: self.workQueue,
            scheduler: self.workScheduler
        )
        action.result
              .subscribe(on: self.workScheduler)
              .subscribe(with: self, onSuccess: { `self`, _ in
                  self.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.processNextAction()
                  }
              }, onFailure: { `self`, _ in
                  self.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.abort(error: .uploadObjectConflict(data: SyncError.ErrorData(itemKeys: [key], libraryId: libraryId)))
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func processSubmitDeletion(for batch: DeleteBatch) {
        let result = SubmitDeletionSyncAction(
            keys: batch.keys,
            object: batch.object,
            version: batch.version,
            libraryId: batch.libraryId,
            userId: self.userId,
            webDavEnabled: self.webDavController.sessionStorage.isEnabled,
            apiClient: self.apiClient,
            dbStorage: self.dbStorage,
            queue: self.workQueue,
            scheduler: self.workScheduler
        ).result
        result.subscribe(on: self.workScheduler)
              .subscribe(onSuccess: { [weak self] version, didCreateDeletions in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.progressHandler.reportWriteBatchSynced(size: batch.keys.count)
                      if didCreateDeletions {
                          self?.addWebDavDeletionsActionIfNeeded(libraryId: batch.libraryId)
                      }
                      self?.finishSubmission(error: nil, newVersion: version, keys: batch.keys, libraryId: batch.libraryId, object: batch.object)
                  }
              }, onFailure: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.progressHandler.reportWriteBatchSynced(size: batch.keys.count)
                      self?.finishSubmission(error: error, newVersion: batch.version, keys: batch.keys, libraryId: batch.libraryId, object: batch.object)
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func finishSubmission(
        error: Error?,
        newVersion: Int?,
        keys: [String],
        libraryId: LibraryIdentifier,
        object: SyncObject,
        failedBeforeReachingApi: Bool = false,
        ignoreWebDav: Bool = false
    ) {
        let nextAction: () -> Void = {
            if let version = newVersion {
                self.updateVersionInNextWriteBatch(to: version)
            }
            self.processNextAction()
        }

        guard let error = error else {
            // If there's no error, proceed to next action
            nextAction()
            return
        }

        // In case of special web dav error (missing zotero directory), ask user whether they want to create the missing directory
        if !ignoreWebDav &&
           self.handleZoteroDirectoryMissing(for: error, continue: { [weak self] in
               self?.finishSubmission(error: error, newVersion: newVersion, keys: keys, libraryId: libraryId, object: object, failedBeforeReachingApi: failedBeforeReachingApi, ignoreWebDav: true)
           }) {
            return
        }

        if let error = error as? SyncActionError {
            // Handle special `SyncActionError`s separately
            switch error {
            case .attachmentAlreadyUploaded:
                // This is not a real error message, it's used to skip through some logic when attachment is already stored remotely. Continue as if no error occured.
                nextAction()
                return

            case .authorizationFailed(let statusCode, let response, let hadIfMatchHeader):
                // Handle upload authorization errors
                self.handleUploadAuthorizationFailure(
                    statusCode: statusCode,
                    response: response,
                    hadIfMatchHeader: hadIfMatchHeader,
                    key: (keys.first ?? ""),
                    libraryId: libraryId,
                    object: object,
                    newVersion: newVersion,
                    failedBeforeReachingApi: failedBeforeReachingApi
                )
                return

            case .attachmentItemNotSubmitted:
                // Attachment item has not been submitted before attachment upload for some reason. Submit and re-start sync.
                if let key = keys.first {
                    self.markItemForUploadAndRestartSync(key: key, libraryId: libraryId)
                    return
                }

            case .objectPreconditionError:
                DDLogError("SyncController: object conflict - trying full sync")
                self.abort(error: .uploadObjectConflict(data: .from(syncObject: object, keys: keys, libraryId: libraryId)))
                return

            default: break
            }
        }

        // Handle all remaining errors
        switch self.syncError(from: error, data: .from(syncObject: object, keys: keys, libraryId: libraryId)) {
        case .fatal(let error):
            self.abort(error: error)

        case .nonFatal(let error):
            self.handleNonFatal(error: error, libraryId: libraryId, version: newVersion, additionalAction: {
                if let version = newVersion {
                    self.updateVersionInNextWriteBatch(to: version)
                }
                if failedBeforeReachingApi {
                    self.handleAllUploadsFailedBeforeReachingZoteroBackend(in: libraryId)
                }
                return true
            })
        }
    }

    private func handleUploadAuthorizationFailure(
        statusCode: Int,
        response: String,
        hadIfMatchHeader: Bool,
        key: String,
        libraryId: LibraryIdentifier,
        object: SyncObject,
        newVersion: Int?,
        failedBeforeReachingApi: Bool
    ) {
        let nonFatalError: SyncError.NonFatal

        switch statusCode {
        case 403:
            switch libraryId {
            case .group(let groupId):
                // File editing denied for library. Stop further edits for given library and notify the user.
                let name = (try? self.dbStorage.perform(request: ReadGroupDbRequest(identifier: groupId), on: self.accessQueue))?.name ?? ""
                self.enqueue(actions: [.resolveGroupFileWritePermission(groupId: groupId, name: name)], at: 0)
                return

            // Shouldn't happen to "my library".
            case .custom:
                nonFatalError = .apiError(response: response, data: .from(syncObject: object, keys: [key], libraryId: libraryId))
            }

        case 413:
            // User reached quota limit for library. Stop further uploads to given library and notify the user.
            nonFatalError = .quotaLimit(libraryId)

        case 404:
            self.markItemForUploadAndRestartSync(key: key, libraryId: libraryId)
            return

        case 412:
            // This happens if file upload passed properly but main app has not been notified and didn't update the database state. Force-download attachment and mark item as uploaded.
            DDLogError("SyncController: download remote attachment file and mark attachment as uploaded")

            // TODO: Check whether this is sufficient when attachment editing is enabled
            self.enqueue(actions: [.fixUpload(key: key, libraryId: libraryId)], at: 0)
            return

        default:
            nonFatalError = .apiError(response: response, data: .from(syncObject: object, keys: [key], libraryId: libraryId))
        }

        self.handleNonFatal(error: nonFatalError, libraryId: libraryId, version: newVersion, additionalAction: {
            if let version = newVersion {
                self.updateVersionInNextWriteBatch(to: version)
            }
            if failedBeforeReachingApi {
                self.handleAllUploadsFailedBeforeReachingZoteroBackend(in: libraryId)
            }
            return true
        })
    }

    private func markItemForUploadAndRestartSync(key: String, libraryId: LibraryIdentifier) {
        self.markItemForUpload(key: key, libraryId: libraryId) { result in
            switch result {
            case .success:
                self.abort(error: .cantSubmitAttachmentItem(data: .from(syncObject: .item, keys: [key], libraryId: libraryId)))

            case .failure:
                self.abort(error: .dbError)
            }
        }
    }

    private func markItemForUpload(key: String, libraryId: LibraryIdentifier, completion: @escaping (Result<(), Error>) -> Void) {
        self.workQueue.async { [weak self] in
            guard let self else { return }

            let request = MarkObjectsAsChangedByUser(libraryId: libraryId, collections: [], items: [key])

            do {
                try self.dbStorage.perform(request: request, on: self.workQueue)

                self.accessQueue.async {
                    completion(.success(()))
                }
            } catch let error {
                DDLogError("SyncController: can't mark item for upload - \(error)")
                completion(.failure(error))
            }
        }
    }

    /// Handles case from issue #381. If there were only uploads enqueued and they all failed before reaching Zotero backend, the sync didn't check whether there are remote changes, so this function
    /// adds download actions to check for remote changes.
    private func handleAllUploadsFailedBeforeReachingZoteroBackend(in libraryId: LibraryIdentifier) {
        // If there were write actions (write, delete item) to Zotero backend, we don't need to check for this anymore. If there were remote changes, we would have gotten 412 from backend already.
        guard !self.didEnqueueWriteActionsToZoteroBackend && self.enqueuedUploads > 0 else { return }
        self.uploadsFailedBeforeReachingZoteroBackend += 1
        // Check whether all uploads failed and whether there are no more actions for this library in queue.
        guard self.enqueuedUploads == self.uploadsFailedBeforeReachingZoteroBackend && self.queue.first?.libraryId != libraryId else { return }
        // Reset flags so that we don't end up here again at some point.
        self.didEnqueueWriteActionsToZoteroBackend = false
        self.enqueuedUploads = 0
        self.uploadsFailedBeforeReachingZoteroBackend = 0
        // Enqueue download actions to check for remote changes
        self.queue.insert(.createLibraryActions(.specific([libraryId]), .onlyDownloads), at: 0)
    }

    private func deleteGroup(with groupId: Int) {
        let result = DeleteGroupSyncAction(groupId: groupId, dbStorage: self.dbStorage, queue: self.workQueue).result
        result.subscribe(on: self.workScheduler)
              .subscribe(onSuccess: { [weak self] _ in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: nil)
                  }
              }, onFailure: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: (error, .from(libraryId: .group(groupId))))
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func markGroupAsLocalOnly(with groupId: Int) {
        let result = MarkGroupAsLocalOnlySyncAction(groupId: groupId, dbStorage: self.dbStorage, queue: self.workQueue).result
        result.subscribe(on: self.workScheduler)
              .subscribe(onSuccess: { [weak self] _ in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: nil)
                  }
              }, onFailure: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: (error, .from(libraryId: .group(groupId))))
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func markChangesAsResolved(in libraryId: LibraryIdentifier) {
        let result = MarkChangesAsResolvedSyncAction(libraryId: libraryId, dbStorage: self.dbStorage, queue: self.workQueue).result
        result.subscribe(on: self.workScheduler)
              .subscribe(onSuccess: { [weak self] _ in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: nil)
                  }
              }, onFailure: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.finishCompletableAction(error: (error, .from(libraryId: libraryId)))
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func revertGroupData(in libraryId: LibraryIdentifier) {
        RevertLibraryUpdatesSyncAction(
            libraryId: libraryId,
            dbStorage: self.dbStorage,
            fileStorage: self.fileStorage,
            schemaController: self.schemaController,
            dateParser: self.dateParser,
            queue: self.workQueue
        )
        .result
        .subscribe(on: self.workScheduler)
        .subscribe(onSuccess: { [weak self] _ in
        self?.accessQueue.async(flags: .barrier) { [weak self] in
            // TODO: - report failures?
            self?.finishCompletableAction(error: nil)
        }
        }, onFailure: { [weak self] error in
            self?.accessQueue.async(flags: .barrier) { [weak self] in
                self?.finishCompletableAction(error: (error, .from(libraryId: libraryId)))
            }
        })
        .disposed(by: self.disposeBag)
    }

    private func revertGroupFiles(in libraryId: LibraryIdentifier) {
        RevertLibraryFilesSyncAction(
            libraryId: libraryId,
            dbStorage: self.dbStorage,
            fileStorage: self.fileStorage,
            schemaController: self.schemaController,
            dateParser: self.dateParser,
            queue: self.workQueue
        )
        .result
        .subscribe(on: self.workScheduler)
        .subscribe(onSuccess: { [weak self] _ in
            self?.accessQueue.async(flags: .barrier) { [weak self] in
              // TODO: - report failures?
                self?.finishCompletableAction(error: nil)
            }
        }, onFailure: { [weak self] error in
            self?.accessQueue.async(flags: .barrier) { [weak self] in
                self?.finishCompletableAction(error: (error, .from(libraryId: libraryId)))
            }
        })
        .disposed(by: self.disposeBag)
    }

    private func finishCompletableAction(error errorData: (Error, SyncError.ErrorData)?) {
        guard let (error, data) = errorData else {
            self.processNextAction()
            return
        }

        switch self.syncError(from: error, data: data) {
        case .fatal(let error):
            self.abort(error: error)

        case .nonFatal(let error):
            self.handleNonFatal(error: error, libraryId: data.libraryId, version: nil)
        }
    }

    private func performWebDavDeletions(libraryId: LibraryIdentifier) {
        let result = DeleteWebDavFilesSyncAction(libraryId: libraryId, dbStorage: self.dbStorage, webDavController: self.webDavController, queue: self.workQueue).result
        result.subscribe(on: self.workScheduler)
              .subscribe(onSuccess: { [weak self] failures in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      if failures.isEmpty {
                          self?.processNextAction()
                      } else {
                          self?.handleNonFatal(error: .webDavDeletion(count: failures.count, library: libraryId.debugName), libraryId: libraryId, version: nil)
                      }
                  }
              }, onFailure: { [weak self] error in
                  self?.accessQueue.async(flags: .barrier) { [weak self] in
                      self?.handleWebDavDeletions(error: error, libraryId: libraryId)
                  }
              })
              .disposed(by: self.disposeBag)
    }

    private func handleWebDavDeletions(error: Error, libraryId: LibraryIdentifier, ignoreWebDav: Bool = false) {
        if !ignoreWebDav && self.handleZoteroDirectoryMissing(for: error, continue: { [weak self] in self?.handleWebDavDeletions(error: error, libraryId: libraryId, ignoreWebDav: true) }) {
            return
        }
        self.handleNonFatal(error: .webDavDeletionFailed(error: error.localizedDescription, library: libraryId.debugName), libraryId: libraryId, version: nil)
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

    /// Updates `.storeDeletionVersion` action in queue for given library to new version.
    /// - parameter libraryId: LibraryIdentifier of action
    /// - parameter version: Version number to which the action should be updated
    private func updateDeletionVersion(for libraryId: LibraryIdentifier, to version: Int) {
        for (idx, action) in self.queue.enumerated() {
            switch action {
            case .storeDeletionVersion(let actionLibraryId, _):
                guard actionLibraryId == libraryId else { continue }
                self.queue[idx] = .storeDeletionVersion(libraryId: libraryId, version: version)
                return
            default: continue
            }
        }
    }

    /// Checks whether given error is fatal or nonfatal.
    /// - parameter error: Error to check.
    /// - parameter libraryId: Library identifier in which the error happened.
    /// - returns: Appropriate `SyncError`.
    private func syncError(from error: Error, data: SyncError.ErrorData) -> SyncError {
        if let error = error as? SyncError.Fatal {
            return .fatal(error)
        }

        if let error = error as? SyncError.NonFatal {
            return .nonFatal(error)
        }

        if let error = error as? SyncActionError {
            switch error {
            case .attachmentMissing(let key, let libraryId, let title):
                return .nonFatal(.attachmentMissing(key: key, libraryId: libraryId, title: title))

            case .annotationNeededSplitting(let message, let keys, let libraryId):
                return .nonFatal(.annotationDidSplit(message: message, keys: keys, libraryId: libraryId))

            case .submitUpdateFailures(let failures):
                let message = failures.map({ $0.message }).joined(separator: "\n")
                return .nonFatal(.unknown(message: message, data: data))

            case .authorizationFailed(_, let message, _): // .authorizationFailed handled separately by `finishSubmission()`
                return .nonFatal(.unknown(message: message, data: data))
                
            case .attachmentAlreadyUploaded, .attachmentItemNotSubmitted: // These are handled separately by `finishSubmission()`
                return .nonFatal(.unknown(message: error.localizedDescription, data: data))

            case .objectPreconditionError: // This is handled separately by `finishSubmission()`
                return .fatal(.uploadObjectConflict(data: data))
            }
        }

        if let error = error as? WebDavError.Verification {
            return .nonFatal(.webDavVerification(error))
        }

        if let error = error as? WebDavError.Download {
            return .nonFatal(.webDavDownload(error))
        }

        if let error = error as? WebDavError.Upload {
            return .nonFatal(.webDavUpload(error))
        }

        if let error = error as? ZoteroApiError {
            switch error {
            case .unchanged: return .nonFatal(.unchanged)
            case .responseMissing: return .nonFatal(.unknown(message: "missing response", data: data))
            }
        }

        // Check other networking errors
        if let responseError = error as? AFResponseError {
            return self.convertAlamoToSyncError(responseError.error, response: responseError.response, data: data)
        }
        if let alamoError = error as? AFError {
            return self.convertAlamoToSyncError(alamoError, response: "No response", data: data)
        }

        // Check realm errors, every "core" error is bad. Can't create new Realm instance, can't continue with sync
        if error is Realm.Error {
            DDLogError("SyncController: received realm error - \(error)")
            return .fatal(.dbError)
        }

        if let error = error as? SchemaError {
            return .nonFatal(.schema(error: error, data: data))
        }
        if let error = error as? Parsing.Error {
            return .nonFatal(.parsing(error: error, data: data))
        }
        DDLogError("SyncController: received unknown error - \(error)")
        return .nonFatal(.unknown(message: error.localizedDescription, data: data))
    }

    /// Checks whether given `AFError` is fatal and requires abort.
    /// - error: `AFError` to check.
    /// - returns: `SyncError` with appropriate error, if abort is required, `nil` otherwise.
    private func convertAlamoToSyncError(_ error: AFError, response: String, data: SyncError.ErrorData) -> SyncError {
        let responseMessage: () -> String = {
            if response == "No Response" {
                return error.localizedDescription
            }
            return response
        }

        switch error {
        case .responseValidationFailed(let reason):
            switch reason {
            case .unacceptableStatusCode(let code):
                switch code {
                case 304:
                    return .nonFatal(.unchanged)

                case 413:
                    return .nonFatal(.quotaLimit(data.libraryId))

                case 507:
                    return .nonFatal(.insufficientSpace)

                case 503:
                    return .fatal(.serviceUnavailable)

                case 403:
                    return .fatal(.forbidden)

                case 412:
                    return .nonFatal(.preconditionFailed(data.libraryId))

                default:
                    return (code >= 400 && code <= 499) ? .fatal(.apiError(response: responseMessage(), data: data)) : .nonFatal(.apiError(response: responseMessage(), data: data))
                }

            case .dataFileNil, .dataFileReadFailed, .missingContentType, .unacceptableContentType, .customValidationFailed:
                return .fatal(.apiError(response: responseMessage(), data: data))
            }

        case .sessionTaskFailed(let error):
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorNotConnectedToInternet {
                return .fatal(.noInternetConnection)
            } else {
                return .fatal(.apiError(response: error.localizedDescription, data: data))
            }
        case .multipartEncodingFailed,
             .parameterEncodingFailed,
             .parameterEncoderFailed,
             .invalidURL,
             .createURLRequestFailed,
             .requestAdaptationFailed,
             .requestRetryFailed,
             .serverTrustEvaluationFailed,
             .sessionDeinitialized,
             .sessionInvalidated,
             .urlRequestValidationFailed:
            return .fatal(.apiError(response: responseMessage(), data: data))

        case .responseSerializationFailed, .createUploadableFailed, .downloadedFileMoveFailed, .explicitlyCancelled:
            return .nonFatal(.apiError(response: responseMessage(), data: data))
        }
    }

    private func handleZoteroDirectoryMissing(for error: Error, continue: @escaping () -> Void) -> Bool {
        guard let error = error as? WebDavError.Verification, case .zoteroDirNotFound(let url) = error else { return false }

        DispatchQueue.main.async {
            self.conflictCoordinator?.askToCreateZoteroDirectory(url: url, create: { [weak self] in
                self?.createZoteroDirectoryAndContinue(errorAction: { [weak self] in
                    self?.accessQueue.async {
                        `continue`()
                    }
                })
            }, cancel: { [weak self] in
                self?.accessQueue.async {
                    `continue`()
                }
            })
        }

        return true
    }

    private func createZoteroDirectoryAndContinue(errorAction: @escaping () -> Void) {
        self.webDavController.createZoteroDirectory(queue: self.workQueue)
                             .subscribe(on: self.workScheduler)
                             .subscribe(onSuccess: { [weak self] _ in
                                 self?.accessQueue.async {
                                     guard let action = self?.processingAction else { return }
                                     self?.workQueue.async {
                                         self?.process(action: action)
                                     }
                                 }
                             }, onFailure: { error in
                                 DDLogError("SyncController: can't create zotero directory - \(error)")
                                 errorAction()
                             })
                             .disposed(by: self.disposeBag)
    }

    /// Handles nonfatal error appropriately.
    /// - parameter error: Type of nonfatal error.
    /// - parameter libraryId: Library identifier.
    /// - parameter version: Optional version number received from backend.
    /// - parameter additionalAction: Optional action taken before next action in queue is processed.
    private func handleNonFatal(error: SyncError.NonFatal, libraryId: LibraryIdentifier, version: Int?, additionalAction: (() -> Bool)? = nil) {
        let appendAndContinue: () -> Void = {
            self.nonFatalErrors.append(error)
            guard additionalAction?() ?? true else { return }
            self.processNextAction()
        }

        switch error {
        case .versionMismatch, .preconditionFailed:
            // If the backend received higher version in response than from previous responses or a 412 on submission, there was a change on backend and we have conflicts.
            // Abort this library and continue with sync. This library will be retried.
            self.removeAllActions(for: libraryId)
            appendAndContinue()

        case .unchanged:
            if let version = version {
                handleUnchangedFailure(lastVersion: version, libraryId: libraryId, additionalAction: additionalAction)
            } else {
                guard additionalAction?() ?? true else { return }
                self.processNextAction()
            }

        case .quotaLimit(let libraryId):
            handleQuotaLimit(for: libraryId, andAppendError: error, additionalAction: additionalAction)

        default:
            appendAndContinue()
        }

        /// Handle quota limit error. It means that the user can't upload more files to backend, so no further uploads should be attempted. Should enqueue check for remote changes.
        /// - parameter libraryId: Library identifier which reached quota limit.
        /// - parameter error: NonFatal error that caused this
        /// - additiionalAction: Additional actions that should be applied to queue
        func handleQuotaLimit(for libraryId: LibraryIdentifier, andAppendError error: SyncError.NonFatal, additionalAction: (() -> Bool)?) {
            DDLogInfo("Sync: received quota limit for \(libraryId)")

            // Remove all other upload actions from queue, our quota is full, so they'll just fail
            self.queue.removeAll(where: { action in
                switch action {
                case .uploadAttachment(let attachment):
                    return attachment.libraryId == libraryId

                default:
                    return false
                }
            })

            // Uploads failed, we need to check for remote changes for this library, in case there were no previous writes.
            self.queue.insert(.createLibraryActions(.specific([libraryId]), .onlyDownloads), at: 0)

            // Add error
            if !self.nonFatalErrors.contains(error) {
                self.nonFatalErrors.append(error)
            }

            guard additionalAction?() ?? true else { return }

            self.processNextAction()
        }

        /// Handle unchanged "error". If backend returns response code 304, it is treated as error. If this error is returned,
        /// we can safely assume, that there are no further remote changes for any object (collections, items, searches, annotations) for this version.
        /// However, some objects may be out of sync (if sync interrupted previously), so other object versions need to be checked. If other object
        /// versions match current version, they can be removed from sync, otherwise they need to sync anyway.
        /// - parameter version: Current version number which returned this error.
        /// - parameter libraryId: Identifier of current library, which is being synced.
        /// - returns: `true` if there was a unchanged error, `false` otherwise.
        func handleUnchangedFailure(lastVersion: Int, libraryId: LibraryIdentifier, additionalAction: (() -> Bool)?) {
            DDLogInfo("Sync: received unchanged error, store version: \(lastVersion)")
            self.lastReturnedVersion = lastVersion

            // If current sync type is `.full` we don't want to skip anything.
            guard self.type != .full else {
                let shouldProcessNext = additionalAction?() ?? true
                if shouldProcessNext {
                    self.processNextAction()
                }
                return
            }

            var toDelete: [Int] = []

            for (index, action) in self.queue.enumerated() {
                guard action.libraryId == libraryId else { break }
                switch action {
                case .syncVersions(let libraryId, let object, let version, _):
                    // If there are no remote changes for previous `Object`, we should check whether current `Object` has been synced up to recent version, so we compare current version with
                    // last returned version. Even if the current object was previously fully synced, we need to check for local unsynced objects anyway.
                    self.queue[index] = .syncVersions(libraryId: libraryId, object: object, version: version, checkRemote: (version < lastVersion))

                case .syncSettings(_, let version),
                     .syncDeletions(_, let version),
                     .storeDeletionVersion(_, let version):
                    if lastVersion == version {
                        toDelete.append(index)
                    }

                default: break
                }
            }

            toDelete.reversed().forEach { self.queue.remove(at: $0) }

            guard additionalAction?() ?? true else { return }
            self.processNextAction()
        }
    }

    private func addWebDavDeletionsActionIfNeeded(libraryId: LibraryIdentifier) {
        var libraryIndex = 0
        for action in self.queue {
            if action.libraryId != libraryId {
                break
            }

            switch action {
            case .performWebDavDeletions:
                // If WebDAV deletions action for this library is already available, don't do anything
                return

            default:
                libraryIndex += 1
            }
        }

        // Insert deletions action to queue at the end of this library actions
        self.queue.insert(.performWebDavDeletions(libraryId), at: libraryIndex)
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
             .syncGroupToDb(let groupId),
             .resolveGroupFileWritePermission(let groupId, _):
            return .group(groupId)
        case .syncVersions(let libraryId, _, _, _),
             .storeVersion(_, let libraryId, _),
             .syncDeletions(let libraryId, _),
             .performDeletions(let libraryId, _, _, _, _, _),
             .restoreDeletions(let libraryId, _, _),
             .storeDeletionVersion(let libraryId, _),
             .syncSettings(let libraryId, _),
             .markChangesAsResolved(let libraryId),
             .revertLibraryToOriginal(let libraryId),
             .createUploadActions(let libraryId, _, _),
             .performWebDavDeletions(let libraryId),
             .fixUpload(_, let libraryId),
             .removeActions(let libraryId),
             .revertLibraryFilesToOriginal(let libraryId):
            return libraryId
        }
    }

    var requiresConflictReceiver: Bool {
        switch self {
        case .resolveDeletedGroup, .resolveGroupMetadataWritePermission, .syncDeletions, .resolveGroupFileWritePermission:
            return true
        case .loadKeyPermissions,
             .createLibraryActions,
             .syncSettings,
             .syncVersions,
             .storeVersion,
             .submitDeleteBatch,
             .submitWriteBatch,
             .deleteGroup,
             .markChangesAsResolved,
             .markGroupAsLocalOnly,
             .revertLibraryToOriginal,
             .uploadAttachment,
             .createUploadActions,
             .syncGroupVersions,
             .syncGroupToDb,
             .syncBatchesToDb,
             .performDeletions,
             .restoreDeletions,
             .storeDeletionVersion,
             .performWebDavDeletions,
             .fixUpload,
             .removeActions,
             .revertLibraryFilesToOriginal:
            return false
        }
    }

    var requiresDebugPermissionPrompt: Bool {
        switch self {
        case .submitDeleteBatch, .submitWriteBatch, .uploadAttachment:
            return true
        case .loadKeyPermissions,
             .createLibraryActions,
             .syncSettings,
             .syncVersions,
             .storeVersion,
             .syncDeletions,
             .deleteGroup,
             .markChangesAsResolved,
             .markGroupAsLocalOnly,
             .revertLibraryToOriginal,
             .createUploadActions,
             .resolveDeletedGroup,
             .resolveGroupMetadataWritePermission,
             .syncGroupVersions,
             .syncGroupToDb,
             .syncBatchesToDb,
             .performDeletions,
             .restoreDeletions,
             .storeDeletionVersion,
             .performWebDavDeletions,
             .fixUpload,
             .resolveGroupFileWritePermission,
             .removeActions,
             .revertLibraryFilesToOriginal:
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

        case .fixUpload(let key, let libraryId):
            return "Fix upload \(key); \(libraryId)"
            
        case .loadKeyPermissions,
             .createLibraryActions,
             .syncSettings,
             .syncVersions,
             .storeVersion,
             .syncDeletions,
             .deleteGroup,
             .markChangesAsResolved,
             .markGroupAsLocalOnly,
             .revertLibraryToOriginal,
             .createUploadActions,
             .resolveDeletedGroup,
             .resolveGroupMetadataWritePermission,
             .syncGroupVersions,
             .syncGroupToDb,
             .syncBatchesToDb,
             .performDeletions,
             .restoreDeletions,
             .storeDeletionVersion,
             .performWebDavDeletions,
             .resolveGroupFileWritePermission,
             .removeActions,
             .revertLibraryFilesToOriginal:
            return "Unknown action"
        }
    }
}
