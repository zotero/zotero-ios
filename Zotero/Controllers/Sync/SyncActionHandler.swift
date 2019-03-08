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
    let settings: Int

    init(collections: Int, items: Int, trash: Int, searches: Int, deletions: Int, settings: Int) {
        self.collections = collections
        self.items = items
        self.trash = trash
        self.searches = searches
        self.deletions = deletions
        self.settings = settings
    }

    init(versions: RVersions?) {
        self.collections = versions?.collections ?? 0
        self.items = versions?.items ?? 0
        self.trash = versions?.trash ?? 0
        self.searches = versions?.searches ?? 0
        self.deletions = versions?.deletions ?? 0
        self.settings = versions?.settings ?? 0
    }
}

protocol SyncActionHandler: class {
    func loadAllLibraryData() -> Single<[(Int, String, Versions)]>
    func loadLibraryData(for libraryIds: [Int]) -> Single<[(Int, String, Versions)]>
    func synchronizeVersions(for library: SyncController.Library, object: SyncController.Object,
                             since sinceVersion: Int?, current currentVersion: Int?,
                             syncAll: Bool) -> Single<(Int, [Any])>
    func markForResync(keys: [Any], library: SyncController.Library, object: SyncController.Object) -> Completable
    func fetchAndStoreObjects(with keys: [Any], library: SyncController.Library,
                              object: SyncController.Object, version: Int) -> Single<([String], [Error])>
    func storeVersion(_ version: Int, for library: SyncController.Library, type: UpdateVersionType) -> Completable
    func synchronizeDeletions(for library: SyncController.Library, since sinceVersion: Int,
                              current currentVersion: Int?) -> Completable
    func synchronizeSettings(for library: SyncController.Library, current currentVersion: Int?,
                             since version: Int?) -> Single<(Bool, Int)>
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
    func loadAllLibraryData() -> Single<[(Int, String, Versions)]> {
        return self.loadLibraryData(identifiers: nil)
    }

    func loadLibraryData(for libraryIds: [Int]) -> Single<[(Int, String, Versions)]> {
        return self.loadLibraryData(identifiers: libraryIds)
    }

    private func loadLibraryData(identifiers: [Int]?) -> Single<[(Int, String, Versions)]> {
        return Single.create { [weak self] subscriber -> Disposable in
            guard let `self` = self else {
                subscriber(.error(SyncActionHandlerError.expired))
                return Disposables.create()
            }

            do {
                let data = try self.dbStorage.createCoordinator()
                                             .perform(request: ReadLibrariesDataDbRequest(identifiers: identifiers))
                                             .map({ ($0.0, $0.1, Versions(versions: $0.2)) })
                subscriber(.success(data))
            } catch let error {
                subscriber(.error(error))
            }

            return Disposables.create()
        }.observeOn(self.scheduler)
    }

    func synchronizeVersions(for library: SyncController.Library, object: SyncController.Object,
                             since sinceVersion: Int?, current currentVersion: Int?,
                             syncAll: Bool) -> Single<(Int, [Any])> {
        switch object {
        case .group:
            return self.synchronizeGroupVersions(library: library, syncAll: syncAll)
        case .collection:
            return self.synchronizeVersions(for: RCollection.self, library: library, object: object,
                                            since: sinceVersion, current: currentVersion, syncAll: syncAll)
        case .item, .trash:
            return self.synchronizeVersions(for: RItem.self, library: library, object: object,
                                            since: sinceVersion, current: currentVersion, syncAll: syncAll)
        case .search:
            return self.synchronizeVersions(for: RSearch.self, library: library, object: object,
                                            since: sinceVersion, current: currentVersion, syncAll: syncAll)
        }
    }

    private func synchronizeGroupVersions(library: SyncController.Library, syncAll: Bool) -> Single<(Int, [Any])> {
        let request = VersionsRequest<Int>(libraryType: library, objectType: .group, version: nil)
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

    private func synchronizeVersions<Obj: SyncableObject>(for: Obj.Type, library: SyncController.Library,
                                                          object: SyncController.Object, since sinceVersion: Int?,
                                                          current currentVersion: Int?,
                                                          syncAll: Bool) -> Single<(Int, [Any])> {
        let forcedSinceVersion = syncAll ? nil : sinceVersion
        let request = VersionsRequest<String>(libraryType: library, objectType: object, version: forcedSinceVersion)
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
                                                                           libraryId: library.libraryId,
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

    func fetchAndStoreObjects(with keys: [Any], library: SyncController.Library,
                              object: SyncController.Object, version: Int) -> Single<([String], [Error])> {
        let keysString = keys.map({ "\($0)" }).joined(separator: ",")
        let request = ObjectsRequest(libraryType: library, objectType: object, keys: keysString)
        return self.apiClient.send(dataRequest: request)
                             .flatMap({ [weak self] response -> Single<([String], [Error])> in
                                 guard let `self` = self else { return Single.error(SyncActionHandlerError.expired) }

                                 let newVersion = SyncActionHandlerController.lastVersion(from: response.1)

                                 // Group version sync doesn't return last version, so we ignore them
                                 if object != .group && version != newVersion {
                                     return Single.error(SyncActionHandlerError.versionMismatch)
                                 }

                                 do {
                                     let decodingData = try self.syncToDb(data: response.0, library: library,
                                                                          object: object)
                                     return Single.just((decodingData.0, decodingData.1))
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             })
    }

    private func syncToDb(data: Data, library: SyncController.Library,
                          object: SyncController.Object) throws -> ([String], [Error]) {
        let coordinator = try self.dbStorage.createCoordinator()

        switch object {
        case .group:
            let decoded = try JSONDecoder().decode(GroupResponse.self, from: data)
            try coordinator.perform(request: StoreGroupDbRequest(response: decoded))
            return ([], [])
        case .collection:
            let decoded = try JSONDecoder().decode(CollectionsResponse.self, from: data)
            try coordinator.perform(request: StoreCollectionsDbRequest(response: decoded.collections))
            return (decoded.collections.map({ $0.key }), decoded.errors)
        case .item, .trash:
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
            let decoded = try ItemResponse.decode(response: jsonObject)
            try coordinator.perform(request: StoreItemsDbRequest(response: decoded.0, trash: object == .trash))
            return (decoded.0.map({ $0.key }), decoded.1)
        case .search:
            let decoded = try JSONDecoder().decode(SearchesResponse.self, from: data)
            try coordinator.perform(request: StoreSearchesDbRequest(response: decoded.searches))
            return (decoded.searches.map({ $0.key }), decoded.errors)
        }
    }

    func storeVersion(_ version: Int, for library: SyncController.Library, type: UpdateVersionType) -> Completable {
        return Completable.create(subscribe: { [weak self] subscriber -> Disposable in
            guard let `self` = self else {
                subscriber(.error(SyncActionHandlerError.expired))
                return Disposables.create()
            }

            do {
                let request = UpdateVersionsDbRequest(version: version, library: library, type: type)
                try self.dbStorage.createCoordinator().perform(request: request)
                subscriber(.completed)
            } catch let error {
                subscriber(.error(error))
            }
            return Disposables.create()
        })
    }

    func markForResync(keys: [Any], library: SyncController.Library, object: SyncController.Object) -> Completable {
        guard !keys.isEmpty else { return Completable.empty() }

        do {
            switch object {
            case .group:
                let request = try MarkLibraryForResyncDbAction(identifiers: keys)
                try self.dbStorage.createCoordinator().perform(request: request)
            case .collection:
                let request = try MarkForResyncDbAction<RCollection>(libraryId: library.libraryId, keys: keys)
                try self.dbStorage.createCoordinator().perform(request: request)
            case .item, .trash:
                let request = try MarkForResyncDbAction<RItem>(libraryId: library.libraryId, keys: keys)
                try self.dbStorage.createCoordinator().perform(request: request)
            case .search:
                let request = try MarkForResyncDbAction<RSearch>(libraryId: library.libraryId, keys: keys)
                try self.dbStorage.createCoordinator().perform(request: request)
            }
            return Completable.empty()
        } catch let error {
            return Completable.error(error)
        }
    }

    func synchronizeDeletions(for library: SyncController.Library, since sinceVersion: Int,
                              current currentVersion: Int?) -> Completable {
        return self.apiClient.send(request: DeletionsRequest(libraryType: library, version: sinceVersion))
                             .observeOn(self.scheduler)
                             .flatMap { [weak self] response -> Single<()> in
                                 let newVersion = SyncActionHandlerController.lastVersion(from: response.1)

                                 if let version = currentVersion, version != newVersion {
                                     return Single.error(SyncActionHandlerError.versionMismatch)
                                 }

                                 guard let `self` = self else { return Single.error(SyncActionHandlerError.expired) }

                                 do {
                                     let request = PerformDeletionsDbRequest(libraryId: library.libraryId,
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

    func synchronizeSettings(for library: SyncController.Library, current currentVersion: Int?,
                             since version: Int?) -> Single<(Bool, Int)> {
        return self.apiClient.send(request: SettingsRequest(libraryType: library, version: version))
                             .observeOn(self.scheduler)
                             .flatMap({ [weak self] response in
                                 guard let `self` = self else { return Single.error(SyncActionHandlerError.expired) }

                                 let newVersion = SyncActionHandlerController.lastVersion(from: response.1)

                                 if let current = currentVersion, newVersion != current {
                                     return Single.error(SyncActionHandlerError.versionMismatch)
                                 }

                                 do {
                                     let request = StoreSettingsDbRequest(response: response.0,
                                                                          libraryId: library.libraryId)
                                     try self.dbStorage.createCoordinator().perform(request: request)
                                     let count = response.0.tagColors?.value.count ?? 0
                                     return Single.just(((count > 0), newVersion))
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             })
    }

    private class func lastVersion(from headers: ResponseHeaders) -> Int {
        return (headers["Last-Modified-Version"] as? String).flatMap(Int.init) ?? 0
    }
}
