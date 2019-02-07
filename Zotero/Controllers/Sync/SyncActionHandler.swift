//
//  SyncActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 06/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

enum SyncActionHandlerError: Error {
    case expired
}

protocol SyncActionHandler: class {
    func loadAllGroupIds() -> Single<[Int]>
    func synchronizeVersions(for group: SyncGroupType, object: SyncObjectType,
                             since version: Int?) -> Single<(Int, [Any])>
    func downloadObjectJson(for keys: [Any], group: SyncGroupType, object: SyncObjectType,
                            version: Int, index: Int) -> Completable
    func markForResync(keys: [Any], object: SyncObjectType) -> Completable
    func synchronizeDbWithFetchedFiles(group: SyncGroupType, object: SyncObjectType,
                                       version: Int, index: Int) -> Completable
}

class SyncActionHandlerController {
    private let scheduler: ConcurrentDispatchQueueScheduler
    private let apiClient: ApiClient
    private let dbStorage: DbStorage
    private let fileStorage: FileStorage
    private let disposeBag: DisposeBag

    init(userId: Int, apiClient: ApiClient, dbStorage: DbStorage, fileStorage: FileStorage) {
        let queue = DispatchQueue(label: "org.zotero.SyncHandlerActionQueue", qos: .utility, attributes: .concurrent)
        self.scheduler = ConcurrentDispatchQueueScheduler(queue: queue)
        self.apiClient = apiClient
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.disposeBag = DisposeBag()
    }
}

extension SyncActionHandlerController: SyncActionHandler {
    func loadAllGroupIds() -> Single<[Int]> {
        return Single.create { [weak self] subscriber -> Disposable in
            guard let `self` = self else {
                subscriber(.error(SyncActionHandlerError.expired))
                return Disposables.create()
            }

            do {
                let ids = try self.dbStorage.createCoordinator().perform(request: ReadGroupIdsDbRequest())
                subscriber(.success(ids))
            } catch let error {
                subscriber(.error(error))
            }

            return Disposables.create()
        }.observeOn(self.scheduler)
    }

    func synchronizeVersions(for group: SyncGroupType, object: SyncObjectType,
                             since version: Int?) -> Single<(Int, [Any])> {
        switch object {
        case .group:
            return self.synchronizeVersions(for: RGroup.self, group: group, object: object, since: version)
        case .collection:
            return self.synchronizeVersions(for: RCollection.self, group: group, object: object, since: version)
        case .item:
            return self.synchronizeVersions(for: RItem.self, group: group, object: object, since: version)
        default:
            fatalError()
        }
    }

    private func synchronizeVersions<Obj: SyncVersionObject>(for: Obj.Type, group: SyncGroupType,
                                                             object: SyncObjectType,
                                                             since version: Int?) -> Single<(Int, [Any])> {
        let request = VersionsRequest<Obj.IdType>(groupType: group, objectType: object, version: version)
        return self.apiClient.send(request: request)
                             .observeOn(self.scheduler)
                             .flatMap { response -> Single<(Int, [Any])> in
                                 let newVersion = (response.responseHeaders["Last-Modified-Version"] as? Int) ?? 0
                                 let request = SyncVersionsDbRequest<Obj>(versions: response.versions)
                                 do {
                                     let identifiers = try self.dbStorage.createCoordinator().perform(request: request)
                                     return Single.just((newVersion, identifiers))
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             }
    }

    func downloadObjectJson(for keys: [Any], group: SyncGroupType, object: SyncObjectType,
                            version: Int, index: Int) -> Completable {
        let file = Files.json(for: group, object: object, version: version, index: index)
        let request = ObjectsRequest(groupType: group, objectType: object, version: version, file: file)
        return self.apiClient.download(request: request)
                             .observeOn(self.scheduler)
    }

    func markForResync(keys: [Any], object: SyncObjectType) -> Completable {
        guard !keys.isEmpty else { return Completable.empty() }
        // TODO: - mark objects in db for resync
        return Completable.error(SyncActionHandlerError.expired)
    }

    func synchronizeDbWithFetchedFiles(group: SyncGroupType, object: SyncObjectType,
                                       version: Int, index: Int) -> Completable {
        return Single.just(Files.json(for: group, object: object, version: version, index: index))
                     .observeOn(self.scheduler)
                     .flatMap({ file -> Single<(Data, File)> in
                         do {
                             let data = try self.fileStorage.read(file)
                             return Single.just((data, file))
                         } catch let error {
                             return Single.error(error)
                         }
                     })
                     .flatMap({ data -> Single<File> in
                         // TODO: - load data json and store to DB
                         return Single.just(data.1)
                     })
                     .flatMap({ file -> Single<()> in
                         do {
                             try self.fileStorage.remove(file)
                             return Single.just(())
                         } catch let error {
                             return Single.error(error)
                         }
                     })
                     .asCompletable()
    }
}
