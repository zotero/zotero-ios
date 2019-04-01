//
//  SyncActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 06/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import CocoaLumberjack
import RxSwift

enum SyncActionHandlerError: Error, Equatable {
    case expired
    case versionMismatch
}

struct LibraryData {
    let identifier: LibraryIdentifier
    let name: String
    let versions: Versions

    init(identifier: LibraryIdentifier, name: String, versions: Versions) {
        self.identifier = identifier
        self.name = name
        self.versions = versions
    }

    init(object: RCustomLibrary) {
        let type = object.type
        self.identifier = .custom(type)
        self.name = type.libraryName
        self.versions = Versions(versions: object.versions)
    }

    init(object: RGroup) {
        self.identifier = .group(object.identifier)
        self.name = object.name
        self.versions = Versions(versions: object.versions)
    }
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
    func loadAllLibraryData() -> Single<[LibraryData]>
    func loadLibraryData(for identifiers: [LibraryIdentifier]) -> Single<[LibraryData]>
    func synchronizeVersions(for library: SyncController.Library, object: SyncController.Object,
                             since sinceVersion: Int?, current currentVersion: Int?,
                             syncAll: Bool) -> Single<(Int, [Any])>
    func markForResync(keys: [Any], library: SyncController.Library, object: SyncController.Object) -> Completable
    func fetchAndStoreObjects(with keys: [Any], library: SyncController.Library,
                              object: SyncController.Object, version: Int) -> Single<([String], [Error])>
    func storeVersion(_ version: Int, for library: SyncController.Library, type: UpdateVersionType) -> Completable
    func synchronizeDeletions(for library: SyncController.Library, since sinceVersion: Int,
                              current currentVersion: Int?) -> Single<[SyncController.Object: [String]]>
    func synchronizeSettings(for library: SyncController.Library, current currentVersion: Int?,
                             since version: Int?) -> Single<(Bool, Int)>
    func submitUpdate(for library: SyncController.Library, object: SyncController.Object, since version: Int,
                      parameters: [[String: Any]]) -> Single<[String]>
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
    func loadAllLibraryData() -> Single<[LibraryData]> {
        return self.loadLibraryData(identifiers: nil)
    }

    func loadLibraryData(for identifiers: [LibraryIdentifier]) -> Single<[LibraryData]> {
        return self.loadLibraryData(identifiers: identifiers)
    }

    private func loadLibraryData(identifiers: [LibraryIdentifier]?) -> Single<[LibraryData]> {
        if identifiers?.count == 0 { return Single.just([]) }

        return Single.create { [weak self] subscriber -> Disposable in
            guard let `self` = self else {
                subscriber(.error(SyncActionHandlerError.expired))
                return Disposables.create()
            }

            do {
                let request = ReadLibrariesDataDbRequest(identifiers: identifiers)
                let data = try self.dbStorage.createCoordinator().perform(request: request)
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
        case .tag: // Tags are not synchronized, this should not be called
            DDLogError("SyncActionHandler: synchronizeVersions tried to sync tags")
            return Single.just((0, []))
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
                             .observeOn(self.scheduler)
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
        case .tag: // Tags are not synchronized, this should not be called
            DDLogError("SyncActionHandler: syncToDb tried to sync tags")
            return ([], [])
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
        }).observeOn(self.scheduler)
    }

    func markForResync(keys: [Any], library: SyncController.Library, object: SyncController.Object) -> Completable {
        guard !keys.isEmpty else { return Completable.empty() }

        do {
            switch object {
            case .group:
                let request = try MarkGroupForResyncDbAction(identifiers: keys)
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
            case .tag: // Tags are not synchronized, this should not be called
                DDLogError("SyncActionHandler: markForResync tried to sync tags")
                break
            }
            return Completable.empty()
        } catch let error {
            return Completable.error(error)
        }
    }

    func synchronizeDeletions(for library: SyncController.Library, since sinceVersion: Int,
                              current currentVersion: Int?) -> Single<[SyncController.Object : [String]]> {
        return self.apiClient.send(request: DeletionsRequest(libraryType: library, version: sinceVersion))
                             .observeOn(self.scheduler)
                             .flatMap { [weak self] response in
                                 let newVersion = SyncActionHandlerController.lastVersion(from: response.1)

                                 if let version = currentVersion, version != newVersion {
                                     return Single.error(SyncActionHandlerError.versionMismatch)
                                 }

                                 guard let `self` = self else { return Single.error(SyncActionHandlerError.expired) }

                                 do {
                                     let request = PerformDeletionsDbRequest(libraryId: library.libraryId,
                                                                             response: response.0,
                                                                             version: newVersion)
                                     let conflicts = try self.dbStorage.createCoordinator().perform(request: request)
                                     return Single.just(conflicts)
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             }
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

    func submitUpdate(for library: SyncController.Library, object: SyncController.Object, since version: Int,
                      parameters: [[String : Any]]) -> Single<[String]> {
        let request = UpdatesRequest(libraryType: library, objectType: object, params: parameters, version: version)
        return self.apiClient.send(dataRequest: request)
                             .observeOn(self.scheduler)
                             .flatMap({ response -> Single<UpdatesResponse> in
                                 do {
                                     let newVersion = SyncActionHandlerController.lastVersion(from: response.1)
                                     let json = try JSONSerialization.jsonObject(with: response.0,
                                                                                 options: .allowFragments)
                                     return Single.just((try UpdatesResponse(json: json, newVersion: newVersion)))
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             })
                             .flatMap({ [weak self] response -> Single<[String]> in
                                 guard let `self` = self else { return Single.error(SyncActionHandlerError.expired) }
                                 let syncedKeys = self.keys(from: (response.successful + response.unchanged),
                                                            parameters: parameters)

                                 do {
                                     let coordinator = try self.dbStorage.createCoordinator()
                                     switch object {
                                     case .collection:
                                         let request = MarkObjectsAsSyncedDbRequest<RCollection>(libraryId: library.libraryId,
                                                                                                 keys: syncedKeys,
                                                                                                 version: response.newVersion)
                                         try coordinator.perform(request: request)
                                     case .item, .trash:
                                        let request = MarkObjectsAsSyncedDbRequest<RItem>(libraryId: library.libraryId,
                                                                                          keys: syncedKeys,
                                                                                          version: response.newVersion)
                                        try coordinator.perform(request: request)
                                     case .search:
                                        let request = MarkObjectsAsSyncedDbRequest<RSearch>(libraryId: library.libraryId,
                                                                                            keys: syncedKeys,
                                                                                            version: response.newVersion)
                                        try coordinator.perform(request: request)
                                     default:
                                         fatalError("Unsupported update request")
                                     }

                                     let updateVersion = UpdateVersionsDbRequest(version: response.newVersion,
                                                                                 library: library,
                                                                                 type: UpdateVersionType.object(object))
                                    try coordinator.perform(request: updateVersion)
                                 } catch let error {
                                     return Single.error(error)
                                 }

                                 if response.failed.first(where: { $0.code == 412 }) != nil {
                                     return Single.error(AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: 412)))
                                 }

                                 return Single.just(response.failed.filter({ $0.code == 409 }).compactMap({ $0.key }))
                             })
    }

    private func keys(from indices: [String], parameters: [[String: Any]]) -> [String] {
        return indices.compactMap({ Int($0) }).map({ parameters[$0] }).compactMap({ $0["key"] as? String })
    }

    private class func lastVersion(from headers: ResponseHeaders) -> Int {
        return (headers["Last-Modified-Version"] as? String).flatMap(Int.init) ?? 0
    }
}
