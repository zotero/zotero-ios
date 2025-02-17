//
//  CancelParentCreationDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 11.10.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct CancelParentCreationDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool {  return true }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).uniqueObject(key: key, libraryId: libraryId), item.parent != nil else { return }
        let parentCollections = item.parent?.collections
        item.parent = nil
        let parentChange = item.changes.filter { change in
            return change.rawChanges == RItemChanges.parent.rawValue
        }
        // Move item back to removed parent's collections.
        if let parentCollections, !parentCollections.isEmpty {
            for collection in parentCollections {
                if collection.items.filter(.key(key)).first == nil {
                    collection.items.append(item)
                    item.changes.append(RObjectChange.create(changes: RItemChanges.collections))
                }
            }
        }
        item.changesSyncPaused = false
        database.delete(parentChange)
    }
}
