//
//  SyncController.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

enum SyncError: Error {
    case expired
}

enum SyncGroupType {
    case user(Int)
    case group(Int)

    var apiPath: String {
        switch self {
        case .group(let identifier):
            return "groups/\(identifier)"
        case .user(let identifier):
            return "users/\(identifier)"
        }
    }
}

enum SyncObjectType {
    case group, collection, search, item, trash

    var apiPath: String {
        switch self {
        case .group:
            return "groups"
        case .collection:
            return "collections"
        case .search:
            return "searches"
        case .item:
            return "items"
        case .trash:
            return "items/trash"
        }
    }
}

class SyncController {
    private let userId: Int
    private let scheduler: ConcurrentDispatchQueueScheduler
    private let apiClient: ApiClient
    private let dbStorage: DbStorage
    private let disposeBag: DisposeBag

    private var syncInProgress: Bool

    init(userId: Int, apiClient: ApiClient, dbStorage: DbStorage) {
        let queue = DispatchQueue(label: "org.zotero.SyncQueue", qos: .utility, attributes: .concurrent)
        self.syncInProgress = false
        self.userId = userId
        self.scheduler = ConcurrentDispatchQueueScheduler(queue: queue)
        self.apiClient = apiClient
        self.dbStorage = dbStorage
        self.disposeBag = DisposeBag()
    }

    func startSync() {
        guard !self.syncInProgress else { return }

        self.syncInProgress = true

        self.createGroupsSync().observeOn(MainScheduler.instance)
                               .subscribe(onError: { [weak self] error in
                                   self?.finishSync(with: error)
                               }, onCompleted: { [weak self] in
                                   guard let `self` = self else { return }
                                   self.createAllGroupObservables().observeOn(self.scheduler)
                                                                   .flatMap { groupType -> Observable<()> in
                                       let collectionSync = self.createCollectionsSync(for: groupType)
                                       let searchSync = self.createSearchesSync(for: groupType)
                                       let itemSync = self.createItemsSync(for: groupType)
                                       let trashSync = self.createTrashSync(for: groupType)
                                       return Observable.concat([collectionSync, searchSync, itemSync, trashSync])
                                   }
                                   .observeOn(MainScheduler.instance)
                                   .subscribe(onError: { [weak self] error in
                                       self?.finishSync(with: error)
                                   }, onCompleted: { [weak self] in
                                       self?.finishSync(with: nil)
                                   })
                                   .disposed(by: self.disposeBag)
                               })
                               .disposed(by: self.disposeBag)
    }

    private func createAllGroupObservables() -> Observable<SyncGroupType> {
        do {
            let userObservable: Observable<SyncGroupType> = Observable.just(.user(self.userId))
            let groupIds = try self.dbStorage.createCoordinator().perform(request: ReadGroupIdsDbRequest())
            let groupObservables: [Observable<SyncGroupType>] = groupIds.map({ Observable.just(.group($0)) })
            return Observable.concat([userObservable] + groupObservables)
        } catch let error {
            return Observable.error(error)
        }
    }

    private func createCollectionsSync(for groupType: SyncGroupType) -> Observable<()> {
        return Observable.just(())
    }

    private func createSearchesSync(for groupType: SyncGroupType) -> Observable<()> {
        return Observable.just(())
    }

    private func createItemsSync(for groupType: SyncGroupType) -> Observable<()> {
        return Observable.just(())
    }

    private func createTrashSync(for groupType: SyncGroupType) -> Observable<()> {
        return Observable.just(())
    }

    private func createGroupsSync() -> Observable<()> {
        let request = VersionsRequest(groupType: .user(self.userId), objectType: .group, version: nil)
        return self.apiClient.send(request: request)
                             .asObservable()
                             .observeOn(self.scheduler)
                             .flatMap({ [weak self] groupVersions -> Observable<GroupResponse> in
                                 guard let `self` = self else { return Observable.error(SyncError.expired) }

                                 let request = SyncGroupVersionsDbRequest(versions: groupVersions)
                                 do {
                                     let versionsToSync = try self.dbStorage.createCoordinator()
                                                                            .perform(request: request)
                                     let groupSyncs = versionsToSync.map({ data -> Observable<GroupRequest.Response> in
                                         let request = GroupRequest(identifier: data.key, version: data.value)
                                         return self.apiClient.send(request: request).asObservable()
                                     })
                                     return Observable.concat(groupSyncs)
                                 } catch let error {
                                     return Observable.error(error)
                                 }
                             })
                             .flatMap({ [weak self] response -> Observable<()> in
                                 guard let `self` = self else { return Observable.error(SyncError.expired) }

                                 do {
                                     let request = StoreGroupDbRequest(response: response)
                                     try self.dbStorage.createCoordinator().perform(request: request)
                                     return Observable.just(())
                                 } catch let error {
                                     return Observable.error(error)
                                 }
                             })
    }

    private func finishSync(with error: Error?) {
        self.syncInProgress = false
    }
}
