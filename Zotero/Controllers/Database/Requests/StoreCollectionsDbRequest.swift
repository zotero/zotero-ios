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
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        for data in self.response {
            try self.store(data: data, to: database)
        }
    }

    private func store(data: CollectionResponse, to database: Realm) throws {
        guard let libraryId = data.library.libraryId else { throw DbError.primaryKeyUnavailable }

        let collection: RCollection
        if let existing = database.objects(RCollection.self).filter(.key(data.key, in: libraryId)).first {
            collection = existing
        } else {
            collection = RCollection()
            database.add(collection)
        }

        collection.key = data.key
        collection.name = data.data.name
        collection.version = data.version
        collection.syncState = .synced
        collection.syncRetries = 0
        collection.lastSyncDate = Date(timeIntervalSince1970: 0)
        collection.libraryId = libraryId
        collection.trash = data.data.isTrash

        // No CR for collections, if it was changed or deleted locally, just restore it
        collection.deleted = false
        collection.resetChanges()

        self.syncParent(libraryId: libraryId, data: data.data, collection: collection, database: database)
    }

    private func syncParent(libraryId: LibraryIdentifier, data: CollectionResponse.Data,
                            collection: RCollection, database: Realm) {
        collection.parent = nil

        guard let key = data.parentCollection else { return }

        let parent: RCollection
        if let existing = database.objects(RCollection.self).filter(.key(key, in: libraryId)).first {
            parent = existing
        } else {
            parent = RCollection()
            parent.key = key
            parent.syncState = .dirty
            parent.libraryId = libraryId
            database.add(parent)
        }
        collection.parent = parent
    }
}
