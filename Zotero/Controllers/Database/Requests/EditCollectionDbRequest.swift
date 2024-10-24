//
//  EditCollectionDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 18/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct EditCollectionDbRequest: DbRequest {
    let libraryId: LibraryIdentifier
    let key: String
    let name: String
    let parentKey: String?

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let collection = database.objects(RCollection.self).uniqueObject(key: key, libraryId: libraryId) else { return }

        var changes: RCollectionChanges = []

        if collection.name != self.name {
            collection.name = self.name
            collection.updateSortName()
            changes.insert(.name)
        }

        if collection.parentKey != self.parentKey {
            collection.parentKey = self.parentKey
            changes.insert(.parent)
        }

        collection.changes.append(RObjectChange.create(changes: changes))
        collection.changeType = .user
    }
}
