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
import RxAlamofire
import RxSwift

enum SyncActionHandlerError: Error {
    case expired                    // Used when we can't get a `self` from `weak self` in a closure, when object was deallocated
    case versionMismatch            // Used when versions from previous request and current request response don't match
    case objectConflict             // Used when there are 412 returned for individual objects when writing data to remote
    case attachmentItemNotSubmitted // Used when the item object for given attachment upload was not submitted to backend
    case attachmentMissing          // Used when we can't find local file for attachment upload
    case attachmentAlreadyUploaded  // Used when we tried to authorize file upload for existing file
}

struct LibraryData {
    let identifier: LibraryIdentifier
    let name: String
    let versions: Versions
    let canEditMetadata: Bool
    let canEditFiles: Bool
    let updates: [SyncController.WriteBatch]
    let deletions: [SyncController.DeleteBatch]
    let hasUpload: Bool

    private static func updates(from chunkedParams: [SyncController.Object: [[[String: Any]]]],
                                version: Int,
                                library: SyncController.Library) -> [SyncController.WriteBatch] {
        var batches: [SyncController.WriteBatch] = []

        let appendBatch: (SyncController.Object) -> Void = { object in
            if let params = chunkedParams[object] {
                batches.append(contentsOf: params.map({ SyncController.WriteBatch(library: library, object: object,
                                                                                  version: version, parameters: $0) }))
            }
        }

        appendBatch(.collection)
        appendBatch(.search)
        appendBatch(.item)

        return batches
    }

    private static func deletions(from chunkedKeys: [SyncController.Object: [[String]]],
                                  version: Int,
                                  library: SyncController.Library) -> [SyncController.DeleteBatch] {
        var batches: [SyncController.DeleteBatch] = []

        let appendBatch: (SyncController.Object) -> Void = { object in
            if let keys = chunkedKeys[object] {
                batches.append(contentsOf: keys.map({ SyncController.DeleteBatch(library: library, object: object,
                                                                                 version: version, keys: $0) }))

            }
        }

        appendBatch(.collection)
        appendBatch(.search)
        appendBatch(.item)

        return batches
    }

    init(object: RCustomLibrary, userId: Int,
         chunkedUpdateParams: [SyncController.Object: [[[String: Any]]]],
         chunkedDeletionKeys: [SyncController.Object: [[String]]],
         hasUpload: Bool) {
        let type = object.type
        let versions = Versions(versions: object.versions)
        let maxVersion = versions.max

        self.identifier = .custom(type)
        self.name = type.libraryName
        self.versions = versions
        self.canEditMetadata = true
        self.canEditFiles = true
        self.hasUpload = hasUpload
        self.updates = LibraryData.updates(from: chunkedUpdateParams, version: maxVersion,
                                           library: .user(userId, type))
        self.deletions = LibraryData.deletions(from: chunkedDeletionKeys, version: maxVersion,
                                               library: .user(userId, type))
    }

    init(object: RGroup,
         chunkedUpdateParams: [SyncController.Object: [[[String: Any]]]],
         chunkedDeletionKeys: [SyncController.Object: [[String]]],
         hasUpload: Bool) {
        let versions = Versions(versions: object.versions)
        let maxVersion = versions.max

        self.identifier = .group(object.identifier)
        self.name = object.name
        self.versions = versions
        self.canEditMetadata = object.canEditMetadata
        self.canEditFiles = object.canEditFiles
        self.hasUpload = hasUpload
        self.updates = LibraryData.updates(from: chunkedUpdateParams, version: maxVersion,
                                           library: .group(object.identifier))
        self.deletions = LibraryData.deletions(from: chunkedDeletionKeys, version: maxVersion,
                                               library: .group(object.identifier))
    }

    // MARK: - Testing only

    init(identifier: LibraryIdentifier, name: String, versions: Versions,
         updates: [SyncController.WriteBatch] = [], deletions: [SyncController.DeleteBatch] = []) {
        self.identifier = identifier
        self.name = name
        self.versions = versions
        self.canEditMetadata = true
        self.canEditFiles = true
        self.updates = updates
        self.deletions = deletions
        self.hasUpload = false
    }
}

struct Versions {
    let collections: Int
    let items: Int
    let trash: Int
    let searches: Int
    let deletions: Int
    let settings: Int

    var max: Int {
        return Swift.max(self.collections,
               Swift.max(self.items,
               Swift.max(self.trash,
               Swift.max(self.searches,
               Swift.max(self.deletions, self.settings)))))
    }

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
    func loadPermissions() -> Single<(KeyResponse, Bool)> // Key response, Bool indicates whether schema needs an update
    func updateSchema() -> Completable
    func loadLibraryData(for type: SyncController.LibrarySyncType, fetchUpdates: Bool) -> Single<[LibraryData]>
    func synchronizeVersions(for library: SyncController.Library, object: SyncController.Object,
                             since sinceVersion: Int?, current currentVersion: Int?,
                             syncType: SyncController.SyncType) -> Single<(Int, [Any])>
    func synchronizeGroupVersions(library: SyncController.Library,
                                  syncType: SyncController.SyncType) -> Single<(Int, [Int], [(Int, String)])>
    func markForResync(keys: [Any], library: SyncController.Library, object: SyncController.Object) -> Completable
    func fetchAndStoreObjects(with keys: [Any], library: SyncController.Library, object: SyncController.Object,
                              version: Int, userId: Int) -> Single<([String], [Error], [StoreItemsError])>
    func storeVersion(_ version: Int, for library: SyncController.Library, type: UpdateVersionType) -> Completable
    func synchronizeDeletions(for library: SyncController.Library, since sinceVersion: Int,
                              current currentVersion: Int?) -> Single<[String]>
    func synchronizeSettings(for library: SyncController.Library, current currentVersion: Int?,
                             since version: Int?) -> Single<(Bool, Int)>
    func submitUpdate(for library: SyncController.Library, object: SyncController.Object, since version: Int,
                      parameters: [[String: Any]]) -> Single<(Int, Error?)>
    func uploadAttachment(for library: SyncController.Library, key: String, file: File,
                          filename: String, md5: String, mtime: Int) -> (Completable, Observable<RxProgress>)
    func submitDeletion(for library: SyncController.Library, object: SyncController.Object,
                        since version: Int, keys: [String]) -> Single<Int>
    func deleteGroup(with groupId: Int) -> Completable
    func markGroupAsLocalOnly(with groupId: Int) -> Completable
    func markChangesAsResolved(in library: SyncController.Library) -> Completable
    func revertLibraryUpdates(in library: SyncController.Library) -> Single<[SyncController.Object: [String]]>
    func loadUploadData(in library: SyncController.Library) -> Single<[SyncController.AttachmentUpload]>
}

class SyncActionHandlerController {
    private let scheduler: ConcurrentDispatchQueueScheduler
    private let apiClient: ApiClient
    private let dbStorage: DbStorage
    private let fileStorage: FileStorage
    private let disposeBag: DisposeBag
    private let schemaController: SchemaController
    private let syncDelayIntervals: [Double]

    init(userId: Int, apiClient: ApiClient, dbStorage: DbStorage, fileStorage: FileStorage,
         schemaController: SchemaController, syncDelayIntervals: [Double]) {
        let queue = DispatchQueue(label: "org.zotero.SyncHandlerActionQueue", qos: .utility, attributes: .concurrent)
        self.scheduler = ConcurrentDispatchQueueScheduler(queue: queue)
        self.apiClient = apiClient
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.schemaController = schemaController
        self.syncDelayIntervals = syncDelayIntervals
        self.disposeBag = DisposeBag()
    }
}

extension SyncActionHandlerController: SyncActionHandler {
    func loadPermissions() -> Single<(KeyResponse, Bool)> {
        return self.apiClient.send(request: KeyRequest())
                             .flatMap { (response, headers) in
                                 do {
                                     // Workaround for broken headers (stored in case-sensitive dictionary) on iOS
                                     let lowercase = headers["zotero-schema-version"] as? String
                                     let uppercase = headers["Zotero-Schema-Version"] as? String
                                     let schemaVersion = (lowercase ?? uppercase).flatMap(Int.init) ?? 0
                                     let schemaNeedsUpdate = schemaVersion > self.schemaController.version
                                     let json = try JSONSerialization.jsonObject(with: response,
                                                                                 options: .allowFragments)
                                     let keyResponse = try KeyResponse(response: json)
                                     return Single.just((keyResponse, schemaNeedsUpdate))
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             }
    }

    func updateSchema() -> Completable {
        return self.schemaController.createFetchSchemaCompletable().observeOn(self.scheduler)
    }

    func loadLibraryData(for type: SyncController.LibrarySyncType, fetchUpdates: Bool) -> Single<[LibraryData]> {
        switch type {
        case .all:
            return self.loadLibraryData(identifiers: nil)
        case .specific(let ids):
            return self.loadLibraryData(identifiers: ids)
        }
    }

    private func loadLibraryData(identifiers: [LibraryIdentifier]?) -> Single<[LibraryData]> {
        if identifiers?.count == 0 { return Single.just([]) }
        let request = ReadLibrariesDataDbRequest(identifiers: identifiers)
        return self.createSingleDbResponseRequest(request)
    }

    func synchronizeVersions(for library: SyncController.Library, object: SyncController.Object,
                             since sinceVersion: Int?, current currentVersion: Int?,
                             syncType: SyncController.SyncType) -> Single<(Int, [Any])> {
        switch object {
        case .collection:
            return self.synchronizeVersions(for: RCollection.self, library: library, object: object,
                                            since: sinceVersion, current: currentVersion, syncType: syncType)
        case .item, .trash:
            return self.synchronizeVersions(for: RItem.self, library: library, object: object,
                                            since: sinceVersion, current: currentVersion, syncType: syncType)
        case .search:
            return self.synchronizeVersions(for: RSearch.self, library: library, object: object,
                                            since: sinceVersion, current: currentVersion, syncType: syncType)
        case .group:
            DDLogError("SyncActionHandler synchronizeVersions(for:object:since:current:syncType:) " +
                       "called for group type")
            return Single.just((0, []))
        case .tag: // Tags are not synchronized, this should not be called
            DDLogError("SyncActionHandler: synchronizeVersions tried to sync tags")
            return Single.just((0, []))
        }
    }

    func synchronizeGroupVersions(library: SyncController.Library,
                                  syncType: SyncController.SyncType) -> Single<(Int, [Int], [(Int, String)])> {
        let syncAll = syncType == .all
        let request = VersionsRequest<Int>(libraryType: library, objectType: .group, version: nil)
        return self.apiClient.send(request: request)
                             .observeOn(self.scheduler)
                             .flatMap { (response: [Int: Int], headers) in
                                 let newVersion = SyncActionHandlerController.lastVersion(from: headers)
                                 let request =  SyncGroupVersionsDbRequest(versions: response, syncAll: syncAll)
                                 do {
                                     let (toUpdate, toRemove) = try self.dbStorage.createCoordinator().perform(request: request)
                                     return Single.just((newVersion, toUpdate, toRemove))
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             }
    }

    private func synchronizeVersions<Obj: SyncableObject>(for: Obj.Type, library: SyncController.Library,
                                                          object: SyncController.Object, since sinceVersion: Int?,
                                                          current currentVersion: Int?,
                                                          syncType: SyncController.SyncType) -> Single<(Int, [Any])> {
        let forcedSinceVersion = syncType == .all ? nil : sinceVersion
        let request = VersionsRequest<String>(libraryType: library, objectType: object, version: forcedSinceVersion)
        return self.apiClient.send(request: request)
                             .observeOn(self.scheduler)
                             .flatMap { (response: [String: Int], headers) -> Single<(Int, [Any])> in
                                  let newVersion = SyncActionHandlerController.lastVersion(from: headers)

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

                                  let request = SyncVersionsDbRequest<Obj>(versions: response,
                                                                           libraryId: library.libraryId,
                                                                           isTrash: isTrash,
                                                                           syncType: syncType,
                                                                           delayIntervals: self.syncDelayIntervals)
                                  do {
                                      let identifiers = try self.dbStorage.createCoordinator().perform(request: request)
                                      return Single.just((newVersion, identifiers))
                                  } catch let error {
                                      return Single.error(error)
                                  }
                             }
    }

    func fetchAndStoreObjects(with keys: [Any], library: SyncController.Library, object: SyncController.Object,
                              version: Int, userId: Int) -> Single<([String], [Error], [StoreItemsError])> {
        let keysString = keys.map({ "\($0)" }).joined(separator: ",")
        let request = ObjectsRequest(libraryType: library, objectType: object, keys: keysString)
        return self.apiClient.send(request: request)
                             .observeOn(self.scheduler)
                             .flatMap({ [weak self] (response, headers) -> Single<([String], [Error], [StoreItemsError])> in
                                 guard let `self` = self else { return Single.error(SyncActionHandlerError.expired) }

                                 let newVersion = SyncActionHandlerController.lastVersion(from: headers)

                                 // Group version sync doesn't return last version, so we ignore them
                                 if object != .group && version != newVersion {
                                     return Single.error(SyncActionHandlerError.versionMismatch)
                                 }

                                 do {
                                     let decodingData = try self.syncToDb(data: response, library: library,
                                                                          object: object, userId: userId)
                                     return Single.just(decodingData)
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             })
    }

    private func syncToDb(data: Data, library: SyncController.Library,
                          object: SyncController.Object, userId: Int) throws -> ([String], [Error], [StoreItemsError]) {
        let coordinator = try self.dbStorage.createCoordinator()

        switch object {
        case .group:
            let decoded = try JSONDecoder().decode(GroupResponse.self, from: data)
            try coordinator.perform(request: StoreGroupDbRequest(response: decoded, userId: userId))
            return ([], [], [])
        case .collection:
            let decoded = try JSONDecoder().decode(CollectionsResponse.self, from: data)

            // Cache JSONs locally for later use (in CR)
            self.storeIndividualCodableJsonObjects(from: decoded.collections,
                                                   type: .collection,
                                                   libraryId: library.libraryId)

            try coordinator.perform(request: StoreCollectionsDbRequest(response: decoded.collections))
            return (decoded.collections.map({ $0.key }), decoded.errors, [])
        case .item, .trash:
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments)

            let (items, parseErrors) = try ItemResponse.decode(response: jsonObject, schemaController: self.schemaController)
            let parsedKeys = items.map({ $0.key })

            // Cache JSONs locally for later use (in CR)
            self.storeIndividualItemJsonObjects(from: jsonObject, keys: parsedKeys, libraryId: library.libraryId)

            // BETA: - forcing preferRemoteData to true for beta, it should be false here so that we report conflicts
            let conflicts = try coordinator.perform(request: StoreItemsDbRequest(response: items,
                                                                                 schemaController: self.schemaController,
                                                                                 preferRemoteData: true))

            return (parsedKeys, parseErrors, conflicts)
        case .search:
            let decoded = try JSONDecoder().decode(SearchesResponse.self, from: data)
            
            // Cache JSONs locally for later use (in CR)
            self.storeIndividualCodableJsonObjects(from: decoded.searches, type: .search, libraryId: library.libraryId)

            try coordinator.perform(request: StoreSearchesDbRequest(response: decoded.searches))
            return (decoded.searches.map({ $0.key }), decoded.errors, [])
        case .tag: // Tags are not synchronized, this should not be called
            DDLogError("SyncActionHandler: syncToDb tried to sync tags")
            return ([], [], [])
        }
    }

    func storeVersion(_ version: Int, for library: SyncController.Library, type: UpdateVersionType) -> Completable {
        return self.createCompletableDbRequest(UpdateVersionsDbRequest(version: version, library: library, type: type))
    }

    func markForResync(keys: [Any], library: SyncController.Library, object: SyncController.Object) -> Completable {
        guard !keys.isEmpty else { return Completable.empty() }

        return Completable.create(subscribe: { [weak self] subscriber -> Disposable in
            guard let `self` = self else {
                subscriber(.error(SyncActionHandlerError.expired))
                return Disposables.create()
            }

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
                subscriber(.completed)
            } catch let error {
                subscriber(.error(error))
            }

            return Disposables.create()
        }).observeOn(self.scheduler)
    }

    func synchronizeDeletions(for library: SyncController.Library, since sinceVersion: Int,
                              current currentVersion: Int?) -> Single<[String]> {
        return self.apiClient.send(request: DeletionsRequest(libraryType: library, version: sinceVersion))
                             .observeOn(self.scheduler)
                             .flatMap { [weak self] (response: DeletionsResponse, headers) in
                                 let newVersion = SyncActionHandlerController.lastVersion(from: headers)

                                 if let version = currentVersion, version != newVersion {
                                     return Single.error(SyncActionHandlerError.versionMismatch)
                                 }

                                 guard let `self` = self else { return Single.error(SyncActionHandlerError.expired) }

                                 do {
                                     let request = PerformDeletionsDbRequest(libraryId: library.libraryId,
                                                                             response: response,
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
                             .flatMap({ [weak self] (response: SettingsResponse, headers) in
                                 guard let `self` = self else { return Single.error(SyncActionHandlerError.expired) }

                                 let newVersion = SyncActionHandlerController.lastVersion(from: headers)

                                 if let current = currentVersion, newVersion != current {
                                     return Single.error(SyncActionHandlerError.versionMismatch)
                                 }

                                 do {
                                     let request = StoreSettingsDbRequest(response: response,
                                                                          libraryId: library.libraryId)
                                     try self.dbStorage.createCoordinator().perform(request: request)
                                     let count = response.tagColors?.value.count ?? 0
                                     return Single.just(((count > 0), newVersion))
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             })
    }

    func submitUpdate(for library: SyncController.Library, object: SyncController.Object, since version: Int,
                      parameters: [[String : Any]]) -> Single<(Int, Error?)> {
        let request = UpdatesRequest(libraryType: library, objectType: object, params: parameters, version: version)
        return self.apiClient.send(request: request)
                             .observeOn(self.scheduler)
                             .flatMap({ (response, headers) -> Single<UpdatesResponse> in
                                 do {
                                     let newVersion = SyncActionHandlerController.lastVersion(from: headers)
                                     let json = try JSONSerialization.jsonObject(with: response,
                                                                                 options: .allowFragments)
                                     return Single.just((try UpdatesResponse(json: json, newVersion: newVersion)))
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             })
                             .flatMap({ [weak self] response -> Single<(Int, Error?)> in
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
                                        // Cache JSONs locally for later use (in CR)
                                        self.storeIndividualItemJsonObjects(from: response.successfulJsonObjects,
                                                                            keys: nil,
                                                                            libraryId: library.libraryId)

                                        let request = MarkObjectsAsSyncedDbRequest<RItem>(libraryId: library.libraryId,
                                                                                          keys: syncedKeys,
                                                                                          version: response.newVersion)
                                        try coordinator.perform(request: request)
                                     case .search:
                                        let request = MarkObjectsAsSyncedDbRequest<RSearch>(libraryId: library.libraryId,
                                                                                            keys: syncedKeys,
                                                                                            version: response.newVersion)
                                        try coordinator.perform(request: request)
                                     case .group, .tag:
                                         fatalError("SyncActionHandler: unsupported update request")
                                     }

                                     let updateVersion = UpdateVersionsDbRequest(version: response.newVersion,
                                                                                 library: library,
                                                                                 type: .object(object))
                                     try coordinator.perform(request: updateVersion)
                                 } catch let error {
                                     return Single.just((response.newVersion, error))
                                 }

                                 if response.failed.first(where: { $0.code == 412 }) != nil {
                                     return Single.just((response.newVersion, SyncActionHandlerError.objectConflict))
                                 }

                                 if response.failed.first(where: { $0.code == 409 }) != nil {
                                     let error = AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: 409))
                                     return Single.just((response.newVersion, error))
                                 }

                                 return Single.just((response.newVersion, nil))
                             })
    }

    func uploadAttachment(for library: SyncController.Library, key: String, file: File,
                          filename: String, md5: String, mtime: Int) -> (Completable, Observable<RxProgress>) {
        let libraryId = library.libraryId
        let dbCheck: Single<()> = Single.create { [weak self] subscriber -> Disposable in
                                      guard let `self` = self else {
                                          subscriber(.error(SyncActionHandlerError.expired))
                                          return Disposables.create()
                                      }

                                     do {
                                         let request = CheckItemIsChangedDbRequest(libraryId: libraryId,
                                                                                   key: key)
                                          let isChanged = try self.dbStorage.createCoordinator()
                                                                            .perform(request: request)
                                          if !isChanged {
                                              subscriber(.success(()))
                                          } else {
                                              subscriber(.error(SyncActionHandlerError.attachmentItemNotSubmitted))
                                          }
                                      } catch let error {
                                          subscriber(.error(error))
                                      }

                                      return Disposables.create()
                                  }

        let upload = dbCheck.flatMap { [weak self] _ -> Single<UInt64> in
                                guard let `self` = self else { return Single.error(SyncActionHandlerError.expired) }
                                let size = self.fileStorage.size(of: file)
                                if size == 0 {
                                    return Single.error(SyncActionHandlerError.attachmentMissing)
                                } else {
                                    return Single.just(size)
                                }
                            }
                            .flatMap { [weak self] filesize -> Single<AuthorizeUploadResponse> in
                                guard let `self` = self else { return Single.error(SyncActionHandlerError.expired) }
                                let request = AuthorizeUploadRequest(libraryType: library, key: key,
                                                                     filename: filename, filesize: filesize,
                                                                     md5: md5, mtime: mtime)
                                return self.apiClient.send(request: request)
                                                     .flatMap({ (data, _) -> Single<AuthorizeUploadResponse> in
                                                        do {
                                                            let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
                                                            let response = try AuthorizeUploadResponse(from: jsonObject)
                                                            return Single.just(response)
                                                        } catch {
                                                            return Single.error(error)
                                                        }
                                                     })
                            }
                            .flatMap { [weak self] response -> Single<Swift.Result<(UploadRequest, String), SyncActionHandlerError>> in
                                guard let `self` = self else { return Single.error(SyncActionHandlerError.expired) }
                                switch response {
                                case .exists:
                                    return Single.just(.failure(SyncActionHandlerError.attachmentAlreadyUploaded))
                                case .new(let response):
                                    let request = AttachmentUploadRequest(url: response.url)
                                    return self.apiClient.upload(request: request) { data in
                                        response.params.forEach({ (key, value) in
                                            if let stringData = value.data(using: .utf8) {
                                                data.append(stringData, withName: key)
                                            }
                                            data.append(file.createUrl(), withName: "file",
                                                        fileName: filename, mimeType: file.mimeType)
                                        })
                                    }.flatMap({ Single.just(.success(($0, response.uploadKey))) })
                                }
                            }

        let response = upload.flatMap({ result -> Single<Swift.Result<(Data, String), SyncActionHandlerError>> in
                                 switch result {
                                 case .success(let uploadRequest, let uploadKey):
                                      return uploadRequest.rx.data()
                                                             .asSingle()
                                                             .flatMap({ Single.just(.success(($0, uploadKey))) })
                                 case .failure(let error):
                                     return Single.just(.failure(error))
                                 }
                             })
                             .flatMap({ [weak self] result -> Single<Swift.Result<(Data, ResponseHeaders), SyncActionHandlerError>> in
                                 guard let `self` = self else { return Single.error(SyncActionHandlerError.expired) }

                                 switch result {
                                 case .success(_, let uploadKey):
                                     let request = RegisterUploadRequest(libraryType: library,
                                                                         key: key,
                                                                         uploadKey: uploadKey)
                                     return self.apiClient.send(request: request).flatMap({ Single.just(.success($0)) })
                                 case .failure(let error):
                                     return Single.just(.failure(error))
                                 }
                             })
                             .flatMap({ [weak self] result -> Single<()> in
                                 guard let `self` = self else { return Single.error(SyncActionHandlerError.expired) }

                                 let markDbAction: () -> Single<()> = {
                                     do {
                                         let request = MarkAttachmentUploadedDbRequest(libraryId: libraryId, key: key)
                                         try self.dbStorage.createCoordinator().perform(request: request)
                                         return Single.just(())
                                     } catch let error {
                                         return Single.error(error)
                                     }
                                 }

                                 switch result {
                                 case .success:
                                     return markDbAction()
                                 case .failure(let error) where error == .attachmentAlreadyUploaded:
                                     return markDbAction()
                                 case .failure(let error):
                                     return Single.error(error)
                                 }
                             })
                             .asCompletable()
                             .observeOn(self.scheduler)

        let progress = upload.asObservable()
                             .flatMap({ result -> Observable<RxProgress> in
                                 switch result {
                                 case .success(let uploadRequest, _):
                                     return uploadRequest.rx.progress()
                                 case .failure(let error):
                                     return Observable.error(error)
                                 }
                             })
                             .observeOn(self.scheduler)

        return (response, progress)
    }

    func submitDeletion(for library: SyncController.Library, object: SyncController.Object,
                        since version: Int, keys: [String]) -> Single<Int> {
        let request = SubmitDeletionsRequest(libraryType: library, objectType: object, keys: keys, version: version)
        return self.apiClient.send(request: request)
                             .observeOn(self.scheduler)
                             .flatMap({ response -> Single<Int> in
                                let newVersion = SyncActionHandlerController.lastVersion(from: response.1)

                                do {
                                    let coordinator = try self.dbStorage.createCoordinator()

                                    switch object {
                                    case .collection:
                                        let request = DeleteObjectsDbRequest<RCollection>(keys: keys,
                                                                                          libraryId: library.libraryId)
                                        try coordinator.perform(request: request)
                                    case .item, .trash:
                                        let request = DeleteObjectsDbRequest<RItem>(keys: keys,
                                                                                    libraryId: library.libraryId)
                                        try coordinator.perform(request: request)
                                    case .search:
                                        let request = DeleteObjectsDbRequest<RSearch>(keys: keys,
                                                                                      libraryId: library.libraryId)
                                        try coordinator.perform(request: request)
                                    case .group, .tag:
                                        fatalError("SyncActionHandler: deleteObjects unsupported object")
                                    }

                                    let updateVersion = UpdateVersionsDbRequest(version: newVersion,
                                                                                library: library,
                                                                                type: .object(object))
                                    try coordinator.perform(request: updateVersion)
                                } catch let error {
                                    return Single.error(error)
                                }

                                return Single.just(newVersion)
                             })
    }

    func deleteGroup(with groupId: Int) -> Completable {
        return self.createCompletableDbRequest(DeleteGroupDbRequest(groupId: groupId))
    }

    func markGroupAsLocalOnly(with groupId: Int) -> Completable {
        return self.createCompletableDbRequest(MarkGroupAsLocalOnlyDbRequest(groupId: groupId))
    }

    func markChangesAsResolved(in library: SyncController.Library) -> Completable {
        return self.createCompletableDbRequest(MarkAllLibraryObjectChangesAsSyncedDbRequest(libraryId: library.libraryId))
    }

    func revertLibraryUpdates(in library: SyncController.Library) -> Single<[SyncController.Object : [String]]> {
        return Single.create { [weak self] subscriber -> Disposable in
            guard let `self` = self else {
                subscriber(.error(SyncActionHandlerError.expired))
                return Disposables.create()
            }

            do {
                let coordinator = try self.dbStorage.createCoordinator()
                let libraryId = library.libraryId
                let jsonDecoder = JSONDecoder()

                let collections = try self.loadCachedJsonsForChangedDecodableObjects(of: RCollection.self,
                                                                                     objectType: .collection,
                                                                                     response: CollectionResponse.self,
                                                                                     in: libraryId,
                                                                                     coordinator: coordinator,
                                                                                     decoder: jsonDecoder)
                let storeCollectionsRequest = StoreCollectionsDbRequest(response: collections.responses)
                try coordinator.perform(request: storeCollectionsRequest)

                let items = try self.loadCachedJsonForItems(in: libraryId, coordinator: coordinator)
                let storeItemsRequest = StoreItemsDbRequest(response: items.responses,
                                                            schemaController: self.schemaController,
                                                            preferRemoteData: true)
                _ = try coordinator.perform(request: storeItemsRequest)

                let searches = try self.loadCachedJsonsForChangedDecodableObjects(of: RSearch.self,
                                                                                  objectType: .search,
                                                                                  response: SearchResponse.self,
                                                                                  in: libraryId,
                                                                                  coordinator: coordinator,
                                                                                  decoder: jsonDecoder)
                let storeSearchesRequest = StoreSearchesDbRequest(response: searches.responses)
                try coordinator.perform(request: storeSearchesRequest)

                let failures: [SyncController.Object : [String]] = [.collection: collections.failed,
                                                                    .search: searches.failed,
                                                                    .item: items.failed]

                subscriber(.success(failures))
            } catch let error {
                subscriber(.error(error))
            }

            return Disposables.create()
        }.observeOn(self.scheduler)
    }

    private func loadCachedJsonForItems(in libraryId: LibraryIdentifier,
                                        coordinator: DbCoordinator) throws -> (responses: [ItemResponse], failed: [String]) {
        let itemsRequest = ReadAnyChangedObjectsInLibraryDbRequest<RItem>(libraryId: libraryId)
        let items = try coordinator.perform(request: itemsRequest)
        var responses: [ItemResponse] = []
        var failed: [String] = []

        items.forEach { item in
            do {
                let file = Files.objectFile(for: .item, libraryId: libraryId, key: item.key, ext: "json")
                let data = try self.fileStorage.read(file)
                let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments)

                if let jsonData = jsonObject as? [String: Any] {
                    let response = try ItemResponse(response: jsonData, schemaController: self.schemaController)
                    responses.append(response)
                } else {
                    failed.append(item.key)
                }
            } catch {
                failed.append(item.key)
            }
        }

        return (responses, failed)
    }

    private func loadCachedJsonsForChangedDecodableObjects<Obj: Syncable&UpdatableObject, Response: Decodable>(of type: Obj.Type,
                                                                                                               objectType: SyncController.Object,
                                                                                                               response: Response.Type,
                                                                                                               in libraryId: LibraryIdentifier,
                                                                                                               coordinator: DbCoordinator,
                                                                                                               decoder: JSONDecoder) throws -> (responses: [Response], failed: [String]) {
        let request = ReadAnyChangedObjectsInLibraryDbRequest<Obj>(libraryId: libraryId)
        let objects = try coordinator.perform(request: request)
        var responses: [Response] = []
        var failed: [String] = []

        objects.forEach({ object in
            do {
                let file = Files.objectFile(for: objectType, libraryId: libraryId,
                                            key: object.key, ext: "json")
                let data = try self.fileStorage.read(file)
                let response = try decoder.decode(Response.self, from: data)
                responses.append(response)
            } catch {
                failed.append(object.key)
            }
        })

        return (responses, failed)
    }

    func loadUploadData(in library: SyncController.Library) -> Single<[SyncController.AttachmentUpload]> {
        let request = ReadAttachmentUploadsDbRequest(library: library)
        return self.createSingleDbResponseRequest(request)
    }

    private func createSingleDbResponseRequest<Request: DbResponseRequest>(_ request: Request) -> Single<Request.Response> {
        return Single.create { [weak self] subscriber -> Disposable in
            guard let `self` = self else {
                subscriber(.error(SyncActionHandlerError.expired))
                return Disposables.create()
            }

            do {
                let data = try self.dbStorage.createCoordinator().perform(request: request)
                subscriber(.success(data))
            } catch let error {
                subscriber(.error(error))
            }

            return Disposables.create()
        }.observeOn(self.scheduler)
    }

    private func createCompletableDbRequest<Request: DbRequest>(_ request: Request) -> Completable {
        return Completable.create(subscribe: { [weak self] subscriber -> Disposable in
            guard let `self` = self else {
                subscriber(.error(SyncActionHandlerError.expired))
                return Disposables.create()
            }

            do {
                try self.dbStorage.createCoordinator().perform(request: request)
                subscriber(.completed)
            } catch let error {
                subscriber(.error(error))
            }
            return Disposables.create()
        }).observeOn(self.scheduler)
    }

    private func storeIndividualItemJsonObjects(from jsonObject: Any, keys: [String]?, libraryId: LibraryIdentifier) {
        guard let array = jsonObject as? [[String: Any]] else { return }

        for object in array {
            guard let key = object["key"] as? String, (keys?.contains(key) ?? true),
                  let data = try? JSONSerialization.data(withJSONObject: object, options: []) else { continue }
            let file = Files.objectFile(for: .item, libraryId: libraryId, key: key, ext: "json")
            try? self.fileStorage.write(data, to: file, options: .atomicWrite)
        }
    }

    private func storeIndividualCodableJsonObjects<Object: KeyedResponse&Codable>(from objects: [Object],
                                                                                  type: SyncController.Object,
                                                                                  libraryId: LibraryIdentifier) {
        for object in objects {
            do {
                let data = try JSONEncoder().encode(object)
                let file = Files.objectFile(for: type, libraryId: libraryId, key: object.key, ext: "json")
                try self.fileStorage.write(data, to: file, options: .atomicWrite)
            } catch let error {
                DDLogError("SyncActionHandler: can't encode/write object - \(error)\n\(object)")
            }
        }
    }

    private func keys(from indices: [String], parameters: [[String: Any]]) -> [String] {
        return indices.compactMap({ Int($0) }).map({ parameters[$0] }).compactMap({ $0["key"] as? String })
    }

    private class func lastVersion(from headers: ResponseHeaders) -> Int {
        // Workaround for broken headers (stored in case-sensitive dictionary) on iOS
        let lowercase = headers["last-modified-version"] as? String
        let uppercase = headers["Last-Modified-Version"] as? String
        return (lowercase ?? uppercase).flatMap(Int.init) ?? 0
    }
}
