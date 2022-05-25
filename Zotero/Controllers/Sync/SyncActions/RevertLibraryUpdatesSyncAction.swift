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
    let queue: DispatchQueue

    var result: Single<[SyncObject : [String]]> {
        return Single.create { subscriber -> Disposable in
            do {
                var changes: [StoreItemsResponse.FilenameChange] = []
                var failedCollections: [String] = []
                var failedSearches: [String] = []
                var failedItems: [String] = []

                try self.dbStorage.perform(on: queue, with: { coordinator in
                    let collections = try self.loadCachedJsonForObject(of: RCollection.self, objectType: .collection, in: self.libraryId, coordinator: coordinator,
                                                                       createResponse: { try CollectionResponse(response: $0) })
                    let searches = try self.loadCachedJsonForObject(of: RSearch.self, objectType: .search, in: self.libraryId, coordinator: coordinator,
                                                                    createResponse: { try SearchResponse(response: $0) })
                    let items = try self.loadCachedJsonForObject(of: RItem.self, objectType: .item, in: self.libraryId, coordinator: coordinator,
                                                                 createResponse: { try ItemResponse(response: $0, schemaController: self.schemaController) })

                    let storeCollectionsRequest = StoreCollectionsDbRequest(response: collections.responses)
                    let storeSearchesRequest = StoreSearchesDbRequest(response: searches.responses)
                    try coordinator.perform(writeRequests: [storeCollectionsRequest, storeSearchesRequest])

                    // Force response data here, since we're reverting
                    let storeItemsRequest = StoreItemsDbResponseRequest(responses: items.responses, schemaController: self.schemaController, dateParser: self.dateParser, preferResponseData: true)
                    changes = try coordinator.perform(request: storeItemsRequest).changedFilenames

                    failedCollections = collections.failed
                    failedSearches = searches.failed
                    failedItems = items.failed

                    coordinator.invalidate()
                })

                self.renameExistingFiles(changes: changes, libraryId: self.libraryId)

                subscriber(.success([.collection: failedCollections, .search: failedSearches, .item: failedItems]))
            } catch let error {
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }

    private func renameExistingFiles(changes: [StoreItemsResponse.FilenameChange], libraryId: LibraryIdentifier) {
        for change in changes {
            let oldFile = Files.attachmentFile(in: libraryId, key: change.key, filename: change.oldName, contentType: change.contentType)

            guard self.fileStorage.has(oldFile) else { continue }

            let newFile = Files.attachmentFile(in: libraryId, key: change.key, filename: change.newName, contentType: change.contentType)

            do {
                try self.fileStorage.move(from: oldFile, to: newFile)
            } catch let error {
                DDLogWarn("RevertLibraryUpdatesSyncAction: can't rename file - \(error)")
                // If it can't be moved, at least delete the old one. It'll have to be re-downloaded anyway.
                try? self.fileStorage.remove(oldFile)
            }
        }
    }

    private func loadCachedJsonForObject<Obj: Syncable&UpdatableObject, Response>(of type: Obj.Type, objectType: SyncObject, in libraryId: LibraryIdentifier, coordinator: DbCoordinator,
                                                                                  createResponse: ([String: Any]) throws -> Response) throws -> (responses: [Response], failed: [String]) {
        let request = ReadAnyChangedObjectsInLibraryDbRequest<Obj>(libraryId: libraryId)
        let objects = try coordinator.perform(request: request)

        var responses: [Response] = []
        var failed: [String] = []

        for object in objects {
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
