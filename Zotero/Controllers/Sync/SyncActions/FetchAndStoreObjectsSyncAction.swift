//
//  FetchAndStoreObjectsSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack
import RxSwift

struct FetchAndStoreObjectsSyncAction: SyncAction {
    typealias Result = ([String], [Error], [StoreItemsError])

    let keys: [Any]
    let object: SyncObject
    let version: Int
    let libraryId: LibraryIdentifier
    let userId: Int

    unowned let apiClient: ApiClient
    unowned let dbStorage: DbStorage
    unowned let fileStorage: FileStorage
    unowned let dateParser: DateParser
    unowned let schemaController: SchemaController
    let queue: DispatchQueue
    let scheduler: SchedulerType

    var result: Single<([String], [Error], [StoreItemsError])> {
        let keysString = self.keys.map({ "\($0)" }).joined(separator: ",")
        let request = ObjectsRequest(libraryId: self.libraryId, userId: self.userId, objectType: self.object, keys: keysString)
        return self.apiClient.send(request: request, queue: self.queue)
                             .observeOn(self.scheduler)
                             .flatMap({ (response, headers) -> Single<([String], [Error], [StoreItemsError])> in
                                 if self.version != headers.lastModifiedVersion {
                                     return Single.error(SyncError.versionMismatch)
                                 }

                                 do {
                                     let decodingData = try self.syncToDb(data: response, libraryId: self.libraryId,
                                                                          object: self.object, userId: self.userId)
                                     return Single.just(decodingData)
                                 } catch let error {
                                     return Single.error(error)
                                 }
                             })
    }

    private func syncToDb(data: Data, libraryId: LibraryIdentifier,
                          object: SyncObject, userId: Int) throws -> ([String], [Error], [StoreItemsError]) {
        let coordinator = try self.dbStorage.createCoordinator()

        switch object {
        case .collection:
            let decoded = try JSONDecoder().decode(CollectionsResponse.self, from: data)

            // Cache JSONs locally for later use (in CR)
            self.storeIndividualCodableJsonObjects(from: decoded.collections,
                                                   type: .collection,
                                                   libraryId: libraryId)

            try coordinator.perform(request: StoreCollectionsDbRequest(response: decoded.collections))
            return (decoded.collections.map({ $0.key }), decoded.errors, [])
        case .item, .trash:
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments)

            let (items, parseErrors) = try ItemResponse.decode(response: jsonObject, schemaController: self.schemaController)
            let parsedKeys = items.map({ $0.key })

            // Cache JSONs locally for later use (in CR)
            self.storeIndividualItemJsonObjects(from: jsonObject, keys: parsedKeys, libraryId: libraryId)

            // BETA: - forcing preferRemoteData to true for beta, it should be false here so that we report conflicts
            let conflicts = try coordinator.perform(request: StoreItemsDbRequest(response: items,
                                                                                 schemaController: self.schemaController,
                                                                                 dateParser: self.dateParser,
                                                                                 preferRemoteData: true))

            return (parsedKeys, parseErrors, conflicts)
        case .search:
            let decoded = try JSONDecoder().decode(SearchesResponse.self, from: data)

            // Cache JSONs locally for later use (in CR)
            self.storeIndividualCodableJsonObjects(from: decoded.searches, type: .search, libraryId: libraryId)

            try coordinator.perform(request: StoreSearchesDbRequest(response: decoded.searches))
            return (decoded.searches.map({ $0.key }), decoded.errors, [])
        }
    }

    private func storeIndividualItemJsonObjects(from jsonObject: Any, keys: [String]?, libraryId: LibraryIdentifier) {
        guard let array = jsonObject as? [[String: Any]] else { return }

        for object in array {
            guard let key = object["key"] as? String, (keys?.contains(key) ?? true) else { continue }

            do {
                let data = try JSONSerialization.data(withJSONObject: object, options: [])
                let file = Files.jsonCacheFile(for: .item, libraryId: libraryId, key: key)
                try self.fileStorage.write(data, to: file, options: .atomicWrite)
            } catch let error {
                DDLogError("FetchAndStoreObjectsSyncAction: can't encode/write item - \(error)\n\(object)")
            }
        }
    }

    private func storeIndividualCodableJsonObjects<Object: KeyedResponse&Codable>(from objects: [Object],
                                                                                  type: SyncObject,
                                                                                  libraryId: LibraryIdentifier) {
        for object in objects {
            do {
                let data = try JSONEncoder().encode(object)
                let file = Files.jsonCacheFile(for: type, libraryId: libraryId, key: object.key)
                try self.fileStorage.write(data, to: file, options: .atomicWrite)
            } catch let error {
                DDLogError("FetchAndStoreObjectsSyncAction: can't encode/write object - \(error)\n\(object)")
            }
        }
    }
}
