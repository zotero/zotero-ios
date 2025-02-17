//
//  RemoveItemFromParentDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 25.01.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct RemoveItemFromParentDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool {  return true }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).uniqueObject(key: key, libraryId: libraryId), item.parent != nil else { return }
        let parentCollections = item.parent?.collections
        
        // Update the parent item, so that it's updated in the item list to hide attachment/note marker
        item.parent?.baseTitle = item.parent?.baseTitle ?? ""
        item.parent?.changeType = .user
        item.parent = nil
        item.changes.append(RObjectChange.create(changes: RItemChanges.parent))

        // Move item to removed parent collections.
        if let parentCollections, !parentCollections.isEmpty {
            for collection in parentCollections {
                if collection.items.filter(.key(key)).first == nil {
                    collection.items.append(item)
                    item.changes.append(RObjectChange.create(changes: RItemChanges.collections))
                }
            }
        }

        item.changeType = .user
    }
}
