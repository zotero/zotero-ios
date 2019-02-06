//
//  SyncActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 06/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

protocol SyncActionHandler: class {
    func loadAllGroupIds() -> Single<[Int]>
    func synchronizeVersions(for group: SyncGroupType, object: SyncObjectType) -> Single<(Int, [Any])>
    func downloadObjectJson(for keys: [Any], group: SyncGroupType, object: SyncObjectType, version: Int) -> Completable
    func markForResync(keys: [Any], object: SyncObjectType) -> Completable
    func synchronizeDbWithFetchedFiles(group: SyncGroupType, object: SyncObjectType, version: Int) -> Completable
}

class SyncActionHandlerController {
    private let scheduler: ConcurrentDispatchQueueScheduler
    private let apiClient: ApiClient
    private let dbStorage: DbStorage

    init(userId: Int, apiClient: ApiClient, dbStorage: DbStorage) {
        let queue = DispatchQueue(label: "org.zotero.SyncHandlerActionQueue", qos: .utility, attributes: .concurrent)
        self.scheduler = ConcurrentDispatchQueueScheduler(queue: queue)
        self.apiClient = apiClient
        self.dbStorage = dbStorage
    }

//    private func tmp() {
//        self.createGroupsSync().observeOn(MainScheduler.instance)
//            .subscribe(onError: { [weak self] error in
//                //                self?.finishSync(with: error)
//                }, onCompleted: { [weak self] in
//                    guard let `self` = self else { return }
//                    self.createAllGroupObservables().observeOn(self.scheduler)
//                        .flatMap { groupType -> Observable<()> in
//                            let collectionSync = self.createCollectionsSync(for: groupType)
//                            let searchSync = self.createSearchesSync(for: groupType)
//                            let itemSync = self.createItemsSync(for: groupType)
//                            let trashSync = self.createTrashSync(for: groupType)
//                            return Observable.concat([collectionSync, searchSync, itemSync, trashSync])
//                        }
//                        .observeOn(MainScheduler.instance)
//                        .subscribe(onError: { [weak self] error in
//                            //                            self?.finishSync(with: error)
//                            }, onCompleted: { [weak self] in
//                                //                                self?.finishSync(with: nil)
//                        })
//                        .disposed(by: self.disposeBag)
//            })
//            .disposed(by: self.disposeBag)
//    }
//
//    private func createAllGroupObservables() -> Observable<SyncGroupType> {
//        do {
//            let userObservable: Observable<SyncGroupType> = Observable.just(.user(self.userId))
//            let groupIds = try self.dbStorage.createCoordinator().perform(request: ReadGroupIdsDbRequest())
//            let groupObservables: [Observable<SyncGroupType>] = groupIds.map({ Observable.just(.group($0)) })
//            return Observable.concat([userObservable] + groupObservables)
//        } catch let error {
//            return Observable.error(error)
//        }
//    }
//
//    private func createCollectionsSync(for groupType: SyncGroupType) -> Observable<()> {
//        return Observable.just(())
//    }
//
//    private func createSearchesSync(for groupType: SyncGroupType) -> Observable<()> {
//        return Observable.just(())
//    }
//
//    private func createItemsSync(for groupType: SyncGroupType) -> Observable<()> {
//        return Observable.just(())
//    }
//
//    private func createTrashSync(for groupType: SyncGroupType) -> Observable<()> {
//        return Observable.just(())
//    }
//
//    private func createGroupsSync() -> Observable<()> {
//        let request = VersionsRequest(groupType: .user(self.userId), objectType: .group, version: nil)
//        return self.apiClient.send(request: request)
//            .asObservable()
//            .observeOn(self.scheduler)
//            .flatMap({ [weak self] groupVersions -> Observable<GroupResponse> in
//                guard let `self` = self else { return Observable.error(SyncError.expired) }
//
//                let request = SyncGroupVersionsDbRequest(versions: groupVersions)
//                do {
//                    let versionsToSync = try self.dbStorage.createCoordinator()
//                        .perform(request: request)
//                    let groupSyncs = versionsToSync.map({ data -> Observable<GroupRequest.Response> in
//                        let request = GroupRequest(identifier: data.key, version: data.value)
//                        return self.apiClient.send(request: request).asObservable()
//                    })
//                    return Observable.concat(groupSyncs)
//                } catch let error {
//                    return Observable.error(error)
//                }
//            })
//            .flatMap({ [weak self] response -> Observable<()> in
//                guard let `self` = self else { return Observable.error(SyncError.expired) }
//
//                do {
//                    let request = StoreGroupDbRequest(response: response)
//                    try self.dbStorage.createCoordinator().perform(request: request)
//                    return Observable.just(())
//                } catch let error {
//                    return Observable.error(error)
//                }
//            })
//    }
}

extension SyncActionHandlerController: SyncActionHandler {
    func loadAllGroupIds() -> Single<[Int]> {
        // TODO: - load all group ids from DB
        return Single.error(SyncError.expired)
    }

    func synchronizeVersions(for group: SyncGroupType, object: SyncObjectType) -> Single<(Int, [Any])> {
        switch object {
        case .group:
            let request = VersionsRequest<Int>(groupType: group, objectType: object, version: nil)
            return self.apiClient.send(request: request)
                                 .flatMap { versions -> Single<(Int, [Any])> in
                                     // TODO: - remove old objects, return dictionary of outdated/new objects and versions
                                     return Single.just((0, Array(versions.keys)))
                                 }
        default:
            let request = VersionsRequest<String>(groupType: group, objectType: object, version: nil)
            return self.apiClient.send(request: request)
                                 .flatMap { versions -> Single<(Int, [Any])> in
                                     // TODO: - remove old objects, return dictionary of outdated/new objects and versions
                                     return Single.just((0, Array(versions.keys)))
                                 }
        }
    }

    func downloadObjectJson(for keys: [Any], group: SyncGroupType,
                            object: SyncObjectType, version: Int) -> Completable {
        // TODO: - Fetch object data for given keys
        // TODO: - Store json file to local disk
        return Completable.error(SyncError.expired)
    }

    func markForResync(keys: [Any], object: SyncObjectType) -> Completable {
        guard !keys.isEmpty else { return Completable.empty() }
        // TODO: - mark objects in db for resync
        return Completable.error(SyncError.expired)
    }

    func synchronizeDbWithFetchedFiles(group: SyncGroupType, object: SyncObjectType, version: Int) -> Completable {
        // TODO: - find all files stored for current version-group-object
        // TODO: - process all files and store them to DB
        // TODO: - remove files after processing
        return Completable.error(SyncError.expired)
    }
}
