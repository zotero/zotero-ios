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
    // Abort (fatal) errors
    case noInternetConnection
    case apiError
    case dbError
    case versionMismatch
    case allGroupsFetchFailed(Error)
}

extension SyncError: Equatable {
    static func ==(lhs: SyncError, rhs: SyncError) -> Bool {
        switch (lhs, rhs) {
        case (.noInternetConnection, .noInternetConnection), (.apiError, .apiError), (.dbError, .dbError),
             (.versionMismatch, .versionMismatch),
             (.allGroupsFetchFailed, .allGroupsFetchFailed):
            return true
        default:
            return false
        }
    }
}

struct ObjectAction {
    static var maxObjectCount = 50

    let order: Int
    let group: SyncGroupType
    let object: SyncObjectType
    let keys: [Any]
    let version: Int

    var keysString: String {
        return self.keys.map({ "\($0)" }).joined(separator: ",")
    }
}

enum QueueAction: Equatable {
    case syncVersions(SyncGroupType, SyncObjectType, Int?)      // Fetch versions from API, update DB based on response
    case syncObjectToFile(ObjectAction)                         // Fetch data for new/updated objects, store to files
    case createGroupActions                                     // Load all groups, spawn actions for each group
    case syncObjectToDb(ObjectAction)                           // Stores file data to db
    case storeVersion(Int, SyncGroupType, SyncObjectType)       // Store new version for given group-object
    case syncDeletions(SyncGroupType, Int)                      // Synchronize deletions of objects in library

    var group: SyncGroupType? {
        switch self {
        case .createGroupActions:
            return nil
        case .syncObjectToFile(let action),
             .syncObjectToDb(let action):
            return action.group
        case .syncVersions(let group, _, _),
             .storeVersion(_, let group, _),
             .syncDeletions(let group, _):
            return group
        }
    }
}

extension ObjectAction: Equatable {
    public static func ==(lhs: ObjectAction, rhs: ObjectAction) -> Bool {
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
        return lhs.order == rhs.order && lhs.group == rhs.group && lhs.object == rhs.object && lhs.version == rhs.version
    }
}

final class SyncController {
    private static let timeoutPeriod: Double = 15.0

    private let userId: Int
    private let accessQueue: DispatchQueue
    private let handler: SyncActionHandler
    private let disposeBag: DisposeBag

    private var queue: [QueueAction]
    private var processingAction: QueueAction?
    private var nonFatalErrors: [Error]
    private var needsResync: Bool
    private var isResyncing: Bool
    private var lastReturnedVersion: Int?
    private var isInitial: Bool

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

    func startSync(isInitial: Bool = false) {
        DDLogInfo("--- Sync: starting ---")
        self.startSync(isResync: false)
    }

    private func startSync(isResync: Bool) {
        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            guard let `self` = self, !self.isSyncing else { return }
            if isResync {
                self.needsResync = false
                self.isResyncing = true
            }
            self.isInitial = true
            self.queue.append(.syncVersions(.user(self.userId), .group, nil))
            self.processNextAction()
        }
    }

    private func finishSync() {
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
            self.cleaupAfterSync()
        }
    }

    private func abortSync(error: Error) {
        inMainThread {
            self.report(fatalError: error)
        }

        DDLogInfo("--- Sync: aborted ---")
        DDLogInfo("Error: \(error)")

        self.reportFinish?(.failure(error))
        self.reportFinish = nil

        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            guard let `self` = self else { return }
            self.cleaupAfterSync()
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
                       self?.startSync(isResync: true)
                   })
                   .disposed(by: self.disposeBag)
    }

    private func setNeedsResync() {
        guard !self.isResyncing else { return }
        self.needsResync = true
    }

    private func cleaupAfterSync() {
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

    private func removeAllActions(for group: SyncGroupType) {
        while !self.queue.isEmpty {
            guard self.queue[0].group == group else { break }
            self.queue.removeFirst()
        }
    }

    private func processNextAction() {
        guard !self.queue.isEmpty else {
            self.processingAction = nil
            self.finishSync()
            return
        }

        let action = self.queue.removeFirst()

        if self.reportFinish != nil {
            self.allActions.append(action)
        }

        // Library is changing, reset "lastReturnedVersion"
        if self.lastReturnedVersion != nil && action.group != self.processingAction?.group {
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
        case .createGroupActions:
            self.startAllGroupsSync()
        case .syncVersions(let groupType, let objectType, let version):
            self.processSyncVersionsAction(group: groupType, object: objectType, since: version)
        case .syncObjectToFile(let action):
            self.processFileStoreAction(action)
        case .syncObjectToDb(let action):
            self.processDbStoreAction(action)
        case .storeVersion(let version, let group, let object):
            self.processStoreVersionAction(group: group, object: object, version: version)
        case .syncDeletions(let group, let version):
            self.syncDeletions(group: group, since: version)
        }
    }

    private func startAllGroupsSync() {
        let userId = self.userId
        self.handler.loadAllGroupIdsAndVersions()
                    .flatMap { groupData in
                        var versionedGroups: [(SyncGroupType, Versions)] = []
                        for data in groupData {
                            if data.0 == RLibrary.myLibraryId {
                                versionedGroups.append((.user(userId), data.1))
                            } else {
                                versionedGroups.append((.group(data.0), data.1))
                            }
                        }
                        return Single.just(versionedGroups)
                    }
                    .subscribe(onSuccess: { [weak self] groupTypes in
                        self?.createVersionActions(from: .success(groupTypes))
                    }, onError: { [weak self] error in
                        self?.createVersionActions(from: .failure(error))
                    })
                    .disposed(by: self.disposeBag)
    }

    private func createVersionActions(from result: Result<[(SyncGroupType, Versions)]>) {
        switch result {
        case .failure(let error):
            self.abortSync(error: SyncError.allGroupsFetchFailed(error))

        case .success(let groupData):
            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                guard let `self` = self else { return }

                var allActions: [QueueAction] = []
                groupData.forEach { data in
                    let actions: [QueueAction] = [.syncVersions(data.0, .collection, data.1.collections),
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

    private func processSyncVersionsAction(group: SyncGroupType, object: SyncObjectType, since version: Int?) {
        self.handler.synchronizeVersions(for: group, object: object, since: version,
                                         current: self.lastReturnedVersion, syncAll: self.isInitial)
                    .subscribe(onSuccess: { [weak self] data in
                        self?.finishSyncVersionsAction(for: group, object: object, result: .success((data.1, data.0)))
                    }, onError: { [weak self] error in
                        self?.finishSyncVersionsAction(for: group, object: object, result: .failure(error))
                    })
                    .disposed(by: self.disposeBag)
    }

    private func finishSyncVersionsAction(for group: SyncGroupType, object: SyncObjectType,
                                          result: Result<([Any], Int)>) {
        switch result {
        case .success(let data):
            self.createObjectActions(from: data.0, currentVersion: data.1, group: group, object: object)

        case .failure(let error):
            if let abortError = self.errorRequiresAbort(error, group: group, object: object) {
                self.abortSync(error: abortError)
                return
            }

            if self.handleVersionMismatchIfNeeded(for: error, group: group) { return }

            // Couldn't sync versions for current object in this group, we don't need to try to sync next objects
            // as they can depend on this one (items depend on collections for example). We can skip to next group.
            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                guard let `self` = self else { return }
                self.nonFatalErrors.append(error)
                self.removeAllActions(for: group)
                self.processNextAction()
            }
        }
    }

    private func createObjectActions(from keys: [Any], currentVersion: Int,
                                     group: SyncGroupType, object: SyncObjectType) {
        let objectActions: [ObjectAction]
        switch object {
        case .group:
            objectActions = keys.enumerated().map { ObjectAction(order: $0.offset, group: group, object: object,
                                                                 keys: [$0.element], version: currentVersion) }

        default:
            let chunkedKeys = keys.chunked(into: ObjectAction.maxObjectCount)
            objectActions = chunkedKeys.enumerated().map { ObjectAction(order: $0.offset, group: group,
                                                                        object: object, keys: $0.element,
                                                                        version: currentVersion) }
        }

        var actions: [QueueAction] = []
        actions.append(contentsOf: objectActions.map({ .syncObjectToFile($0) }))
        actions.append(contentsOf: objectActions.map({ .syncObjectToDb($0) }))
        if object == .group {
            actions.append(.createGroupActions)
        } else {
            actions.append(.storeVersion(currentVersion, group, object))
        }

        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            if object != .group {
                self?.lastReturnedVersion = currentVersion
            }
            self?.enqueue(actions: actions, at: 0)
        }
    }

    private func processFileStoreAction(_ action: ObjectAction) {
        self.handler.downloadObjectJson(for: action.keysString, group: action.group,
                                        object: action.object, version: action.version, index: action.order)
                    .subscribe(onCompleted: { [weak self] in
                        self?.finishFileStoreAction(action, error: nil)
                    }, onError: { [weak self] error in
                        self?.finishFileStoreAction(action, error: error)
                    })
                    .disposed(by: self.disposeBag)
    }

    private func finishFileStoreAction(_ action: ObjectAction, error: Error?) {
        guard let error = error else {
            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                self?.processNextAction()
            }
            return
        }

        if let abortError = self.errorRequiresAbort(error, group: action.group, object: action.object) {
            self.abortSync(error: abortError)
            return
        }

        if self.handleVersionMismatchIfNeeded(for: error, group: action.group) { return }

        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            self?.nonFatalErrors.append(error)
        }

        // We couldn't fetch group of up to ObjectAction.maxObjectCount objects, some objects will probably be
        // missing parents or completely, but we continue with the sync
        // We mark these objects as missing and we'll try to fetch and update them on next sync
        self.markForResync(keys: action.keys, group: action.group, object: action.object)
    }

    private func processDbStoreAction(_ action: ObjectAction) {
        self.handler.synchronizeDbWithFetchedFiles(group: action.group, object: action.object,
                                                   version: action.version, index: action.order)
                    .subscribe(onCompleted: { [weak self] in
                        self?.finishDbStoreAction(for: action.group, object: action.object,
                                                  keys: action.keys, error: nil)
                    }, onError: { [weak self] error in
                        self?.finishDbStoreAction(for: action.group, object: action.object,
                                                  keys: action.keys, error: error)
                    })
                    .disposed(by: self.disposeBag)
    }

    private func finishDbStoreAction(for group: SyncGroupType, object: SyncObjectType,
                                     keys: [Any], error: Error?) {
        guard let error = error else {
            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                self?.processNextAction()
            }
            return
        }

        if let abortError = self.errorRequiresAbort(error) {
            self.abortSync(error: abortError)
            return
        }

        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            self?.nonFatalErrors.append(error)
        }

        // If we failed to sync some objects with non-fatal error, we just continue and try to sync the rest of the
        // library, they will hopefully be fixed on next sync.
        self.markForResync(keys: keys, group: group, object: object)
    }

    private func processStoreVersionAction(group: SyncGroupType, object: SyncObjectType, version: Int) {
        self.handler.storeVersion(version, for: group, object: object)
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
            self.abortSync(error: abortError)
            return
        }

        // If we only failed to store correct versions we can continue as usual, we'll just try to fetch from
        // older version on next sync and most objects will be up to date
        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            self?.nonFatalErrors.append(error)
            self?.processNextAction()
        }
    }

    private func markForResync(keys: [Any], group: SyncGroupType, object: SyncObjectType) {
        self.handler.markForResync(keys: keys, group: group, object: object)
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
                            self.removeAllActions(for: group)
                            self.processNextAction()
                        }
                    })
                    .disposed(by: self.disposeBag)
    }

    private func syncDeletions(group: SyncGroupType, since sinceVersion: Int) {
        self.handler.synchronizeDeletions(for: group, since: sinceVersion, current: self.lastReturnedVersion)
            .subscribe(onCompleted: { [weak self] in
                self?.finishProcessingDeletions(error: nil)
            }, onError: { [weak self] error in
                self?.finishProcessingDeletions(error: error)
            })
            .disposed(by: self.disposeBag)
    }

    private func finishProcessingDeletions(error: Error?) {
        guard let error = error else {
            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                self?.processNextAction()
            }
            return
        }

        if let abortError = self.errorRequiresAbort(error) {
            self.abortSync(error: abortError)
            return
        }

        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            self?.nonFatalErrors.append(error)
            self?.processNextAction()
        }
    }

    // MARK: - Helpers

    private func performOnAccessQueue(flags: DispatchWorkItemFlags = [], action: @escaping () -> Void) {
        self.accessQueue.async(flags: flags) {
            action()
        }
    }

    private func errorRequiresAbort(_ error: Error, group: SyncGroupType? = nil,
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

        // If the backend received higher version in response than from previous responses for initial group sync,
        // we might as well abort the whole sync already, because these groups are already outdated
        if let handlerError = error as? SyncActionHandlerError, handlerError == .versionMismatch,
           object == .group, let group = group, case .user = group {
            return SyncError.versionMismatch
        }

        // Check realm errors, every "core" error is bad. Can't create new Realm instance, can't continue with sync
        if error is Realm.Error {
            return SyncError.dbError
        }

        return nil
    }

    private func handleVersionMismatchIfNeeded(for error: Error, group: SyncGroupType) -> Bool {
        guard let handlerError = error as? SyncActionHandlerError,
              handlerError == .versionMismatch else { return false }

        // If the backend received higher version in response than from previous responses,
        // there was a change on backend and we'll probably have conflicts, abort this group
        // and continue with sync
        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            guard let `self` = self else { return }
            self.nonFatalErrors.append(error)
            self.removeAllActions(for: group)
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
