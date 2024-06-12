//
//  MoveItemsToParentDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 01/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MoveItemsToParentDbRequest: DbRequest {
    let itemKeys: Set<String>
    let parentKey: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool {  return true }

    func process(in database: Realm) throws {
        guard let parent = database.objects(RItem.self).uniqueObject(key: parentKey, libraryId: libraryId) else {
            return
        }

        let items = database.objects(RItem.self) .filter(.keys(self.itemKeys, in: self.libraryId))
        for item in items {
            var changes: RItemChanges = .parent

            item.parent = parent

            if !item.collections.isEmpty {
                for collection in item.collections {
                    guard let index = collection.items.index(of: item) else { continue }
                    collection.items.remove(at: index)
                }
                changes.insert(.collections)
            }

            item.changes.append(RObjectChange.create(changes: changes))
            item.changeType = .user
        }

        // Update the parent item, so that it's updated in the item list to show attachment/note marker
        parent.baseTitle = parent.baseTitle
        parent.changeType = .user
    }
}
