//
//  RevertLibraryUpdatesSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 30/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

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
                let jsonDecoder = JSONDecoder()

                let collections = try self.loadCachedJsonsForChangedDecodableObjects(of: RCollection.self,
                                                                                     objectType: .collection,
                                                                                     response: CollectionResponse.self,
                                                                                     in: self.libraryId,
                                                                                     coordinator: coordinator,
                                                                                     decoder: jsonDecoder)
                let storeCollectionsRequest = StoreCollectionsDbRequest(response: collections.responses)
                try coordinator.perform(request: storeCollectionsRequest)

                let items = try self.loadCachedJsonForItems(in: self.libraryId, coordinator: coordinator)
                let storeItemsRequest = StoreItemsDbRequest(response: items.responses,
                                                            schemaController: self.schemaController,
                                                            dateParser: self.dateParser,
                                                            preferRemoteData: true)
                _ = try coordinator.perform(request: storeItemsRequest)

                let searches = try self.loadCachedJsonsForChangedDecodableObjects(of: RSearch.self,
                                                                                  objectType: .search,
                                                                                  response: SearchResponse.self,
                                                                                  in: self.libraryId,
                                                                                  coordinator: coordinator,
                                                                                  decoder: jsonDecoder)
                let storeSearchesRequest = StoreSearchesDbRequest(response: searches.responses)
                try coordinator.perform(request: storeSearchesRequest)

                let failures: [SyncObject : [String]] = [.collection: collections.failed,
                                                                    .search: searches.failed,
                                                                    .item: items.failed]

                subscriber(.success(failures))
            } catch let error {
                subscriber(.error(error))
            }

            return Disposables.create()
        }
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
                                                                                                               objectType: SyncObject,
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
}
