//
//  CreateCollectionDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 17/04/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct CreateCollectionDbRequest: DbRequest {
    let libraryId: LibraryIdentifier
    let key: String
    let name: String
    let parentKey: String?

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let collection = RCollection()
        collection.key = self.key
        collection.name = self.name
        collection.syncState = .synced
        collection.libraryId = self.libraryId

        var changes: RCollectionChanges = .name

        if let key = self.parentKey {
            collection.parentKey = key
            changes.insert(.parent)

            if let parent = database.objects(RCollection.self).filter(.key(key, in: self.libraryId)).first {
                parent.collapsed = false
            }
        }

        let change = RObjectChange.create(changes: changes)
        collection.changes.append(change)

        collection.changeType = .user
        database.add(collection)
    }
}
