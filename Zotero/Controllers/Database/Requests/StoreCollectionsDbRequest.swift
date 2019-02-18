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
        let collection: RCollection
        if let existing = database.objects(RCollection.self)
                                  .filter("key = %@ AND library.identifier = %d", data.key,
                                                                                  data.library.libraryId).first {
            collection = existing
        } else {
            collection = RCollection()
            database.add(collection)
        }

        collection.key = data.key
        collection.name = data.data.name
        collection.version = data.version
        collection.needsSync = false

        let libraryData = try database.autocreatedObject(ofType: RLibrary.self, forPrimaryKey: data.library.libraryId)
        if libraryData.0 {
            libraryData.1.name = data.library.name
            libraryData.1.needsSync = true
        }
        collection.library = libraryData.1

        collection.parent = nil
        if let key = data.data.parentCollection {
            let parent: RCollection
            if let existing = database.objects(RCollection.self)
                                      .filter("library.identifier = %d AND key = %@", data.library.libraryId,
                                                                                      key).first {
                parent = existing
            } else {
                parent = RCollection()
                parent.key = key
                parent.library = collection.library
            }
            collection.parent = parent
        }
    }
}
