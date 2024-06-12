//
//  StoreCollectionsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct StoreCollectionsDbRequest: DbRequest {
    let response: [CollectionResponse]

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        for data in self.response {
            try self.store(data: data, to: database)
        }
    }

    private func store(data: CollectionResponse, to database: Realm) throws {
        guard let libraryId = data.library.libraryId else { throw DbError.primaryKeyUnavailable }

        let collection: RCollection
        if let existing = database.objects(RCollection.self).uniqueObject(key: data.key, libraryId: libraryId) {
            collection = existing
        } else {
            collection = RCollection()
            collection.collapsed = true
            database.add(collection)
        }

        // No CR for collections, if it was changed or deleted locally, just restore it
        if collection.deleted {
            for item in collection.items {
                item.trash = false
                item.deleted = false
            }
        }
        collection.deleted = false
        collection.deleteAllChanges(database: database)

        // Update local instance with remote values
        StoreCollectionsDbRequest.update(collection: collection, response: data, libraryId: libraryId, database: database)
    }

    static func update(collection: RCollection, response: CollectionResponse, libraryId: LibraryIdentifier, database: Realm) {
        collection.key = response.key
        collection.name = response.data.name
        collection.version = response.version
        collection.syncState = .synced
        collection.syncRetries = 0
        collection.lastSyncDate = Date(timeIntervalSince1970: 0)
        collection.changeType = .sync
        collection.libraryId = libraryId
        collection.trash = response.data.isTrash

        self.sync(parentCollection: response.data.parentCollection, libraryId: libraryId, collection: collection, database: database)
    }

    static func sync(parentCollection: String?, libraryId: LibraryIdentifier, collection: RCollection, database: Realm) {
        collection.parentKey = nil

        guard let key = parentCollection else { return }

        let parent: RCollection
        if let existing = database.objects(RCollection.self).uniqueObject(key: key, libraryId: libraryId) {
            parent = existing
        } else {
            parent = RCollection()
            parent.key = key
            parent.syncState = .dirty
            parent.libraryId = libraryId
            database.add(parent)
        }
        collection.parentKey = parent.key
    }
}
