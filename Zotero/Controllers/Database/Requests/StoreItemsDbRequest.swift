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
        let item: RItem
        if let existing = database.objects(RItem.self)
                                  .filter("key = %@ AND library.identifier = %d", data.key,
                                                                                  data.library.libraryId).first {
            item = existing
        } else {
            item = RItem()
            database.add(item)
        }

        item.key = data.key
        item.rawType = data.type.rawValue
        item.version = data.version
        item.trash = data.isTrash
        item.needsSync = false

        let titleKeys = RItem.titleKeys
        let allFieldKeys = Array(data.fields.keys)
        let toRemove = item.fields.filter("NOT key IN %@", allFieldKeys)
        database.delete(toRemove)
        allFieldKeys.forEach { key in
            let value = data.fields[key] ?? ""
            if let existing = item.fields.filter("key = %@", key).first {
                existing.value = value
            } else {
                let field = RItemField()
                field.key = key
                field.value = value
                field.item = item
                database.add(field)
            }
            if titleKeys.contains(key) {
                item.title = value
            }
        }

        let libraryData = try database.autocreatedObject(ofType: RLibrary.self, forPrimaryKey: data.library.libraryId)
        if libraryData.0 {
            libraryData.1.needsSync = true
        }
        item.library = libraryData.1

        item.parent = nil
        if let key = data.parentKey {
            let parent: RItem
            if let existing = database.objects(RItem.self)
                                      .filter("library.identifier = %d AND key = %@", data.library.libraryId,
                                                                                      key).first {
                parent = existing
            } else {
                parent = RItem()
                parent.key = key
                parent.needsSync = true
                parent.library = item.library
            }
            item.parent = parent
        }

        item.collections.removeAll()
        if !data.collectionKeys.isEmpty {
            var remainingCollections = data.collectionKeys
            let existingCollections = database.objects(RCollection.self)
                                              .filter("library.identifier = %d AND key IN %@", data.library.libraryId,
                                                                                               data.collectionKeys)
            for collection in existingCollections {
                item.collections.append(collection)
                remainingCollections.remove(collection.key)
            }

            for key in remainingCollections {
                let collection = RCollection()
                collection.key = key
                collection.needsSync = true
                collection.library = item.library
            }
        }
    }
}
