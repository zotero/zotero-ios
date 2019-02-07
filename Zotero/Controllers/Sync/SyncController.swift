//
//  SyncController.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import RealmSwift
import RxSwift

enum SyncError: Error {
    // Abort (fatal) errors
    case noInternetConnection
    case apiError
    case dbError
    // Non-fatal errors
    case allGroupsFetchFailed(Error)
}

fileprivate struct ObjectAction {
    static var maxObjectCount = 50

    let order: Int
    let group: SyncGroupType
    let object: SyncObjectType
    let keys: [Any]
    let version: Int
}

fileprivate enum QueueAction {
    case syncVersions(SyncGroupType, SyncObjectType, Int?)      // Fetch versions from API, update DB based on response
    case syncObjectToFile(ObjectAction)                         // Fetch data for new/updated objects, store to files
    case createGroupActions                                     // Load all groups, spawn actions for each group
    case syncObjectToDb(ObjectAction)                           // Stores file data to db
    case storeVersion(Int, SyncGroupType, SyncObjectType)       // Store new version for given group-object

    var group: SyncGroupType? {
        switch self {
        case .createGroupActions:
            return nil
        case .syncObjectToFile(let action), .syncObjectToDb(let action):
            return action.group
        case .syncVersions(let group, _, _):
            return group
        case .storeVersion(_, let group, _):
            return group
        }
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
    }

    // MARK: - Sync management

    func startSync() {
        self.startSync(isResync: false)
    }

    private func startSync(isResync: Bool) {
        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            guard let `self` = self, !self.isSyncing else { return }
            if isResync {
                self.needsResync = false
                self.isResyncing = true
            }
            self.queue.append(.syncVersions(.user(self.userId), .group, nil))
            self.processNextAction()
        }
    }

    private func finishSync() {
        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            guard let `self` = self else { return }

            let errors = self.nonFatalErrors
            if !errors.isEmpty {
                inMainThread {
                    self.report(nonFatalErrors: errors)
                }
            }

            self.cleaupAfterSync()
            self.enqueueResyncIfNeeded()
        }
    }

    private func abortSync(error: Error) {
        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            self?.cleaupAfterSync()
        }

        inMainThread {
            self.report(fatalError: error)
        }

        self.enqueueResync()
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
        self.processingAction = action
        self.process(action: action)
    }

    // MARK: - Action processing

    private func process(action: QueueAction) {
        switch action {
        case .createGroupActions:
            self.startAllGroupsSync()
        case .syncVersions(let groupType, let objectType, let version):
            self.processVersionAction(group: groupType, object: objectType, since: version)
        case .syncObjectToFile(let action):
            self.processFileStoreAction(action)
        case .syncObjectToDb(let action):
            self.processDbStoreAction(action)
        case .storeVersion(let version, let group, let object):
            fatalError()
        }
    }

    private func startAllGroupsSync() {
        let userId = self.userId
        self.handler.loadAllGroupIds()
                    .flatMap { groupIds in
                        let groups: [SyncGroupType] = [.user(userId)] + groupIds.map({ .group($0) })
                        return Single.just(groups)
                    }
                    .subscribe(onSuccess: { [weak self] groupTypes in
                        self?.createVersionActions(for: groupTypes, error: nil)
                    }, onError: { [weak self] error in
                        self?.createVersionActions(for: [.user(userId)], error: SyncError.allGroupsFetchFailed(error))
                    })
                    .disposed(by: self.disposeBag)
    }

    private func createVersionActions(for groups: [SyncGroupType], error: Error?) {
        self.performOnAccessQueue(flags: .barrier) { [weak self] in
            guard let `self` = self else { return }

            if let error = error {
                self.nonFatalErrors.append(error)
            }

            groups.forEach { group in
                let actions: [QueueAction] = [.syncVersions(group, .collection, nil),
                                              .syncVersions(group, .item, nil),
                                              .syncVersions(group, .trash, nil),
                                              .syncVersions(group, .search, nil)]
                self.enqueue(actions: actions)
            }
        }
    }

    private func processVersionAction(group: SyncGroupType, object: SyncObjectType, since version: Int?) {
        self.handler.synchronizeVersions(for: group, object: object, since: version)
                    .subscribe(onSuccess: { [weak self] data in
                        self?.finishVersionAction(for: group, result: .success((data.1, data.0, object)))
                    }, onError: { [weak self] error in
                        self?.finishVersionAction(for: group, result: .failure(error))
                    })
                    .disposed(by: self.disposeBag)
    }

    private func finishVersionAction(for group: SyncGroupType, result: Result<([Any], Int, SyncObjectType)>) {
        switch result {
        case .success(let data):
            self.createObjectActions(from: data.0, currentVersion: data.1, group: group, object: data.2)

        case .failure(let error):
            if let abortError = self.errorRequiresAbort(error) {
                self.abortSync(error: abortError)
                return
            }

            self.nonFatalErrors.append(error)

            // Couldn't sync versions for current object in this group, we don't need to try to sync next objects
            // as they can depend on this one (items depend on collections for example). We can skip to next group.
            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                guard let `self` = self else { return }
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
            self?.enqueue(actions: actions, at: 0)
        }
    }

    private func processFileStoreAction(_ action: ObjectAction) {
        self.handler.downloadObjectJson(for: action.keys, group: action.group,
                                        object: action.object, version: action.version, index: action.order)
                    .subscribe(onCompleted: { [weak self] in
                        self?.finishObjectAction(action, result: .success(()))
                    }, onError: { [weak self] error in
                        self?.finishObjectAction(action, result: .failure(error))
                    })
                    .disposed(by: self.disposeBag)
    }

    private func finishObjectAction(_ action: ObjectAction, result: Result<()>) {
        switch result {
        case .success:
            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                self?.processNextAction()
            }

        case .failure(let error):
            if let abortError = self.errorRequiresAbort(error) {
                self.abortSync(error: abortError)
                return
            }

            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                self?.nonFatalErrors.append(error)
            }

            // We couldn't fetch group of up to ObjectAction.maxObjectCount objects, some objects will probably be
            // missing parents or completely, but we continue with the sync
            // We mark these objects as missing and we'll try to fetch and update them on next sync
            self.markForResync(keys: action.keys, group: action.group, object: action.object)
        }
    }

    private func processDbStoreAction(_ action: ObjectAction) {
        self.handler.synchronizeDbWithFetchedFiles(group: action.group, object: action.object,
                                                   version: action.version, index: action.order)
                    .subscribe(onCompleted: { [weak self] in
                        self?.finishDbStoreAction(for: action.group, object: action.object,
                                                  keys: action.keys, result: .success(()))
                    }, onError: { [weak self] error in
                        self?.finishDbStoreAction(for: action.group, object: action.object,
                                                  keys: action.keys, result: .failure(error))
                    })
                    .disposed(by: self.disposeBag)
    }

    private func finishDbStoreAction(for group: SyncGroupType, object: SyncObjectType,
                                     keys: [Any], result: Result<()>) {
        switch result {
        case .success:
            self.performOnAccessQueue(flags: .barrier) { [weak self] in
                self?.processNextAction()
            }

        case .failure(let error):
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
    }

    private func markForResync(keys: [Any], group: SyncGroupType, object: SyncObjectType) {
        self.handler.markForResync(keys: keys, object: object)
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

    // MARK: - Helpers

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
}
