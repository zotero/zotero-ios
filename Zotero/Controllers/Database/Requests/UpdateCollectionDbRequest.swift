//
//  UpdateCollectionDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 11/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct UpdateCollectionDbRequest: DbRequest {
    let libraryId: Int
    let key: String
    let name: String?
    let parent: String?

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        if self.key == self.parent {
            throw DbError.invalidRequest("trying to assign self as my parent")
        }

        guard let collection = database.objects(RCollection.self)
                                       .filter("key = %@ AND library.identifier = %d", self.key,
                                                                                       self.libraryId).first else {
            throw DbError.objectNotFound
        }

        if let name = self.name {
            collection.name = name
            collection.changedFields = collection.changedFields.union(.name)
        }

        if let parentKey = self.parent {
            let parentCollection: RCollection
            if let parent = database.objects(RCollection.self)
                                    .filter("key = %@ AND library.identifier = %d", self.key, self.libraryId).first {
                parentCollection = parent
            } else {
                parentCollection = RCollection()
                parentCollection.key = parentKey
                parentCollection.syncState = .dirty
                database.add(parentCollection)
            }
            collection.parent = parentCollection
            collection.changedFields = collection.changedFields.union(.parent)
        }

        collection.dateModified = Date()
    }
}
