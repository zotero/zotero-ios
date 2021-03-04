//
//  RevertLibraryUpdatesSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RxSwift

struct RevertLibraryUpdatesSyncAction: SyncAction {
    typealias Result = [SyncObject : [String]]

    let libraryId: LibraryIdentifier

    unowned let dbStorage: DbStorage
    unowned let fileStorage: FileStorage
    unowned let schemaController: SchemaController
    unowned let dateParser: DateParser

    var result: Single<[SyncObject : [String]]> {
        return Single.create { subscriber -> Disposable in
            do {
                let coordinator = try self.dbStorage.createCoordinator()

                let collections = try self.loadCachedJsonForObject(of: RCollection.self, objectType: .collection, in: self.libraryId, coordinator: coordinator,
                                                                   createResponse: { try CollectionResponse(response: $0) })
                let searches = try self.loadCachedJsonForObject(of: RSearch.self, objectType: .search, in: self.libraryId, coordinator: coordinator,
                                                                createResponse: { try SearchResponse(response: $0) })
                let items = try self.loadCachedJsonForObject(of: RItem.self, objectType: .item, in: self.libraryId, coordinator: coordinator,
                                                             createResponse: {
                                                                try ItemResponse(response: $0, schemaController: self.schemaController)
                                                             })

                let storeCollectionsRequest = StoreCollectionsDbRequest(response: collections.responses)
                let storeItemsRequest = StoreItemsDbRequest(responses: items.responses, schemaController: self.schemaController, dateParser: self.dateParser)
                let storeSearchesRequest = StoreSearchesDbRequest(response: searches.responses)
                try coordinator.perform(requests: [storeCollectionsRequest, storeItemsRequest, storeSearchesRequest])

                subscriber(.success([.collection: collections.failed, .search: searches.failed, .item: items.failed]))
            } catch let error {
                subscriber(.error(error))
            }

            return Disposables.create()
        }
    }

    private func loadCachedJsonForObject<Obj: Syncable&UpdatableObject, Response>(of type: Obj.Type,
                                                                                  objectType: SyncObject,
                                                                                  in libraryId: LibraryIdentifier,
                                                                                  coordinator: DbCoordinator,
                                                                                  createResponse: ([String: Any])
                                                                            throws -> Response) throws -> (responses: [Response], failed: [String]) {
        let request = ReadAnyChangedObjectsInLibraryDbRequest<Obj>(libraryId: libraryId)
        let objects = try coordinator.perform(request: request)

        var responses: [Response] = []
        var failed: [String] = []

        objects.forEach { object in
            do {
                let file = Files.jsonCacheFile(for: objectType, libraryId: libraryId, key: object.key)
                let data = try self.fileStorage.read(file)
                let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments)

                if let jsonData = jsonObject as? [String: Any] {
                    let response = try createResponse(jsonData)
                    responses.append(response)
                } else {
                    failed.append(object.key)
                }
            } catch let error {
                DDLogError("RevertLibraryUpdatesSyncAction: can't load cached file - \(error)")
                failed.append(object.key)
            }
        }

        return (responses, failed)
    }
}
