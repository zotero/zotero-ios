//
//  SyncActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 06/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

enum SyncActionHandlerError: Error, Equatable {
    case expired
    case versionMismatch
}

struct Versions {
    let collections: Int
    let items: Int
    let trash: Int
    let searches: Int
    let deletions: Int

    init(collections: Int, items: Int, trash: Int, searches: Int, deletions: Int) {
        self.collections = collections
        self.items = items
        self.trash = trash
        self.searches = searches
        self.deletions = deletions
    }

    init(versions: RVersions?) {
        self.collections = versions?.collections ?? 0
        self.items = versions?.items ?? 0
        self.trash = versions?.trash ?? 0
        self.searches = versions?.searches ?? 0
        self.deletions = versions?.deletions ?? 0
    }
}

protocol SyncActionHandler: class {
    func loadAllGroupIdsAndVersions() -> Single<[(Int, Versions)]>
    func synchronizeVersions(for group: SyncGroupType, object: SyncObjectType,
                             since sinceVersion: Int?, current currentVersion: Int?,
                             syncAll: Bool) -> Single<(Int, [Any])>
    func downloadObjectJson(for keys: String, group: SyncGroupType, object: SyncObjectType,
                            version: Int, index: Int) -> Completable
    func markForResync(keys: [Any], group: SyncGroupType, object: SyncObjectType) -> Completable
    func synchronizeDbWithFetchedFiles(group: SyncGroupType, object: SyncObjectType,
                                       version: Int, index: Int) -> Completable
    func storeVersion(_ version: Int, for group: SyncGroupType, object: SyncObjectType) -> Completable
    func synchronizeDeletions(for group: SyncGroupType, since sinceVersion: Int, current currentVersion: Int?) -> Completable
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
    func loadAllGroupIdsAndVersions() -> Single<[(Int, Versions)]> {
        return Single.create { [weak self] subscriber -> Disposable in
            guard let `self` = self else {
                subscriber(.error(SyncActionHandlerError.expired))
                return Disposables.create()
            }

            do {
                let data = try self.dbStorage.createCoordinator()
                                             .perform(request: ReadGroupDataDbRequest())
                                             .map({ ($0.0, Versions(versions: $0.1)) })
                subscriber(.success(data))
            } catch let error {
                subscriber(.error(error))
            }

            return Disposables.create()
        }.observeOn(self.scheduler)
    }

    func synchronizeVersions(for group: SyncGroupType, object: SyncObjectType,
                             since sinceVersion: Int?, current currentVersion: Int?,
                             syncAll: Bool) -> Single<(Int, [Any])> {
        switch object {
        case .group:
            return self.synchronizeGroupVersions(group: group, syncAll: syncAll)
        case .collection:
            return self.synchronizeVersions(for: RCollection.self, group: group, object: object,
                                            since: sinceVersion, current: currentVersion, syncAll: syncAll)
        case .item, .trash:
            return self.synchronizeVersions(for: RItem.self, group: group, object: object,
                                            since: sinceVersion, current: currentVersion, syncAll: syncAll)
        case .search:
            return Single.just(((currentVersion ?? 0), []))
        }
    }

    private func synchronizeGroupVersions(group: SyncGroupType, syncAll: Bool) -> Single<(Int, [Any])> {
        let request = VersionsRequest<Int>(groupType: group, objectType: .group, version: nil)
        return self.apiClient.send(request: request)
                             .observeOn(self.scheduler)
            .flatMap { response -> Single<(Int, [Any])> in
                let newVersion = SyncActionHandlerController.lastVersion(from: response.1)
                let request =  SyncGroupVersionsDbRequest(versions: response.0, syncAll: syncAll)
                do {
                    let identifiers = try self.dbStorage.createCoordinator().perform(request: request)
                    return Single.just((newVersion, identifiers))
                } catch let error {
                    return Single.error(error)
                }
        }
    }

    private func synchronizeVersions<Obj: Syncable>(for: Obj.Type, group: SyncGroupType, object: SyncObjectType,
                                                    since sinceVersion: Int?, current currentVersion: Int?,
                                                    syncAll: Bool) -> Single<(Int, [Any])> {
        let forcedSinceVersion = syncAll ? nil : sinceVersion
        let request = VersionsRequest<String>(groupType: group, objectType: object, version: forcedSinceVersion)
        return self.apiClient.send(request: request)
                             .observeOn(self.scheduler)
                             .flatMap { response -> Single<(Int, [Any])> in
                                  let newVersion = SyncActionHandlerController.lastVersion(from: response.1)

                                  if let current = currentVersion, newVersion != current {
                                      return Single.error(SyncActionHandlerError.versionMismatch)
                                  }

                                  var isTrash: Bool?
                                  switch object {
                                  case .item:
                                      isTrash = false
                                  case .trash:
                                      isTrash = true
                                  default: break
                                  }

                                  let request = SyncVersionsDbRequest<Obj>(versions: response.0,
                                                                           libraryId: group.libraryId,
                                                                           isTrash: isTrash,
                                                                           syncAll: syncAll)
                                  do {
                                      let identifiers = try self.dbStorage.createCoordinator().perform(request: request)
                                      return Single.just((newVersion, identifiers))
                                  } catch let error {
                                      return Single.error(error)
                                  }
                             }
    }

    func downloadObjectJson(for keys: String, group: SyncGroupType, object: SyncObjectType,
                            version: Int, index: Int) -> Completable {
        let request = ObjectsRequest(groupType: group, objectType: object, keys: keys)
        return self.apiClient.send(dataRequest: request)
                             .flatMap { [weak self] response -> Single<()> in
                                 guard let `self` = self else { return Single.error(SyncActionHandlerError.expired) }

                                 let newVersion = SyncActionHandlerController.lastVersion(from: response.1)

                                 if object != .group && version != newVersion {
                                     return Single.error(SyncActionHandlerError.versionMismatch)
                                 }

                                 let file = Files.json(for: group, object: object, version: version, index: index)
                                 do {
                                     try self.fileStorage.write(response.0, to: file,
                                                                options: [.noFileProtection])
                                     return Single.just(())
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             }
                             .asCompletable()
    }

    func synchronizeDbWithFetchedFiles(group: SyncGroupType, object: SyncObjectType,
                                       version: Int, index: Int) -> Completable {
        return Single.just(Files.json(for: group, object: object, version: version, index: index))
                     .observeOn(self.scheduler)
                     .flatMap({ [weak self] file -> Single<(Data, File)> in
                        guard let `self` = self else { return Single.error(SyncActionHandlerError.expired) }

                         do {
                             let data = try self.fileStorage.read(file)
                             return Single.just((data, file))
                         } catch let error {
                             return Single.error(error)
                         }
                     })
                     .flatMap({ [weak self] data -> Single<File> in
                        guard let `self` = self else { return Single.error(SyncActionHandlerError.expired) }

                        do {
                            try self.syncToDb(data: data.0, group: group, object: object)
                            return Single.just(data.1)
                        } catch let error {
                            return Single.error(error)
                        }
                     })
                     .flatMap({ [weak self] file -> Single<()> in
                        guard let `self` = self else { return Single.error(SyncActionHandlerError.expired) }

                         do {
                             try self.fileStorage.remove(file)
                             return Single.just(())
                         } catch let error {
                             return Single.error(error)
                         }
                     })
                     .asCompletable()
    }

    private func syncToDb(data: Data, group: SyncGroupType, object: SyncObjectType) throws {
        let coordinator = try self.dbStorage.createCoordinator()

        switch object {
        case .group:
            let decoded = try JSONDecoder().decode(GroupResponse.self, from: data)
            try coordinator.perform(request: StoreGroupDbRequest(response: decoded))
        case .collection:
            let decoded = try JSONDecoder().decode([CollectionResponse].self, from: data)
            try coordinator.perform(request: StoreCollectionsDbRequest(response: decoded))
        case .item:
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
            let decoded = try ItemResponse.decode(response: jsonObject)
            try coordinator.perform(request: StoreItemsDbRequest(response: decoded, trash: false))
        case .trash:
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
            let decoded = try ItemResponse.decode(response: jsonObject)
            try coordinator.perform(request: StoreItemsDbRequest(response: decoded, trash: true))
        case .search:
            throw SyncActionHandlerError.expired
        }
    }

    func storeVersion(_ version: Int, for group: SyncGroupType, object: SyncObjectType) -> Completable {
        return Completable.create(subscribe: { [weak self] subscriber -> Disposable in
            guard let `self` = self else {
                subscriber(.error(SyncActionHandlerError.expired))
                return Disposables.create()
            }

            do {
                let request = UpdateVersionsDbRequest(version: version, object: object, group: group)
                try self.dbStorage.createCoordinator().perform(request: request)
                subscriber(.completed)
            } catch let error {
                subscriber(.error(error))
            }
            return Disposables.create()
        })
    }

    func markForResync(keys: [Any], group: SyncGroupType, object: SyncObjectType) -> Completable {
        guard !keys.isEmpty else { return Completable.empty() }

        do {
            switch object {
            case .group:
                let request = try MarkLibraryForResyncDbAction(identifiers: keys)
                try self.dbStorage.createCoordinator().perform(request: request)
            case .collection:
                let request = try MarkForResyncDbAction<RCollection>(libraryId: group.libraryId, keys: keys)
                try self.dbStorage.createCoordinator().perform(request: request)
            case .item, .trash:
                let request = try MarkForResyncDbAction<RItem>(libraryId: group.libraryId, keys: keys)
                try self.dbStorage.createCoordinator().perform(request: request)
            case .search:
                return Completable.empty()
            }

            return Completable.empty()
        } catch let error {
            return Completable.error(error)
        }
    }

    func synchronizeDeletions(for group: SyncGroupType, since sinceVersion: Int, current currentVersion: Int?) -> Completable {
        return self.apiClient.send(request: DeletionsRequest(groupType: group, version: sinceVersion))
                             .observeOn(self.scheduler)
                             .flatMap { [weak self] response -> Single<()> in
                                 let newVersion = SyncActionHandlerController.lastVersion(from: response.1)

                                 if let version = currentVersion, version != newVersion {
                                     return Single.error(SyncActionHandlerError.versionMismatch)
                                 }

                                 guard let `self` = self else { return Single.error(SyncActionHandlerError.expired) }

                                 do {
                                     let request = PerformDeletionsDbRequest(libraryId: group.libraryId,
                                                                             response: response.0,
                                                                             version: newVersion)
                                     try self.dbStorage.createCoordinator().perform(request: request)
                                     return Single.just(())
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             }
                             .asCompletable()
    }

    private class func lastVersion(from headers: ResponseHeaders) -> Int {
        return (headers["Last-Modified-Version"] as? String).flatMap(Int.init) ?? 0
    }
}
