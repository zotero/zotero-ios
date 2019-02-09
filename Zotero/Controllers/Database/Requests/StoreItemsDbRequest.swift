//
//  StoreItemsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct StoreItemsDbRequest: DbRequest {
    let response: [ItemResponse]
    let trash: Bool

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        for data in self.response {
            try self.store(data: data, to: database)
        }
    }

    private func store(data: ItemResponse, to database: Realm) throws {
        let item = try database.autocreatedObject(ofType: RItem.self, forPrimaryKey: data.identifier).1
        item.title = data.data.title
        item.version = data.version
        item.trash = data.data.isTrash
        item.needsSync = false
        item.parent = nil
        item.library = nil
        item.collections.removeAll()

        let libraryData = try database.autocreatedObject(ofType: RLibrary.self, forPrimaryKey: data.library.libraryId)
        if libraryData.0 {
            libraryData.1.needsSync = true
        }
        item.library = libraryData.1

        if let parentId = data.data.parentItem {
            let parentData = try database.autocreatedObject(ofType: RItem.self, forPrimaryKey: parentId)
            if parentData.0 {
                parentData.1.needsSync = true
            }

            item.parent = parentData.1
        }

        if let collections = data.data.collections {
            for collectionId in collections {
                let collectionData = try database.autocreatedObject(ofType: RCollection.self,
                                                                    forPrimaryKey: collectionId)
                if collectionData.0 {
                    collectionData.1.needsSync = true
                }
                item.collections.append(collectionData.1)
            }
        }
    }
}
