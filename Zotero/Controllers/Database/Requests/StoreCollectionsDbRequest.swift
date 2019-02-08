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
        let collection = try database.autocreatedObject(ofType: RCollection.self, forPrimaryKey: data.identifier).1
        collection.name = data.data.name
        collection.version = data.version
        collection.needsSync = false

        let libraryData = try database.autocreatedObject(ofType: RLibrary.self, forPrimaryKey: data.library.libraryId)
        if libraryData.0 {
            libraryData.1.needsSync = true
        }
        collection.library = libraryData.1

        if let parentId = data.data.parentCollection {
            let parentData = try database.autocreatedObject(ofType: RCollection.self, forPrimaryKey: parentId)
            if parentData.0 {
                parentData.1.needsSync = true
            }

            collection.parent = parentData.1
        }
    }
}
