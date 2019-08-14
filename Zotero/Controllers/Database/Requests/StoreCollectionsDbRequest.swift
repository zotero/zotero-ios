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

        let predicate = Predicates.key(data.key, in: libraryId)
        let collection: RCollection
        if let existing = database.objects(RCollection.self).filter(predicate).first {
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

        // No CR for collections, if it was changed or deleted locally, just restore it
        if collection.deleted {
            collection.items.forEach { item in
                if item.deleted {
                    item.deleted = false
                }
            }
        }
        collection.deleted = false
        collection.resetChanges()

        try self.syncLibrary(identifier: libraryId, name: data.library.name, collection: collection, database: database)
        self.syncParent(libraryId: libraryId, data: data.data, collection: collection, database: database)
    }

    private func syncLibrary(identifier: LibraryIdentifier, name: String,
                             collection: RCollection, database: Realm) throws {
        let (isNew, object) = try database.autocreatedLibraryObject(forPrimaryKey: identifier)
        if isNew {
            switch object {
            case .group(let group):
                group.name = name
                group.syncState = .outdated
            case .custom: break
            }
        }
        collection.libraryObject = object
    }

    private func syncParent(libraryId: LibraryIdentifier, data: CollectionResponse.Data,
                            collection: RCollection, database: Realm) {
        collection.parent = nil

        guard let key = data.parentCollection else { return }

        let predicate = Predicates.key(key, in: libraryId)
        let parent: RCollection
        if let existing = database.objects(RCollection.self).filter(predicate).first {
            parent = existing
        } else {
            parent = RCollection()
            parent.key = key
            parent.syncState = .dirty
            parent.libraryObject = collection.libraryObject
            database.add(parent)
        }
        collection.parent = parent
    }
}
