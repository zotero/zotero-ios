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

        let predicate = Predicates.keyInLibrary(key: data.key, libraryId: libraryId)
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
        collection.needsSync = false

        try self.syncLibrary(identifier: libraryId, name: data.library.name, collection: collection, database: database)
        self.syncParent(libraryId: libraryId, data: data.data, collection: collection, database: database)
    }

    private func syncLibrary(identifier: LibraryIdentifier, name: String,
                             collection: RCollection, database: Realm) throws {
        let libraryData = try database.autocreatedLibraryObject(forPrimaryKey: identifier)
        if libraryData.0 {
            switch libraryData.1 {
            case .group(let group):
                group.name = name
                group.needsSync = true
            case .custom: break
            }
        }
        collection.libraryObject = libraryData.1
    }

    private func syncParent(libraryId: LibraryIdentifier, data: CollectionResponse.Data,
                            collection: RCollection, database: Realm) {
        collection.parent = nil

        guard let key = data.parentCollection else { return }

        let predicate = Predicates.keyInLibrary(key: key, libraryId: libraryId)
        let parent: RCollection
        if let existing = database.objects(RCollection.self).filter(predicate).first {
            parent = existing
        } else {
            parent = RCollection()
            parent.key = key
            parent.libraryObject = collection.libraryObject
            database.add(parent)
        }
        collection.parent = parent
    }
}
