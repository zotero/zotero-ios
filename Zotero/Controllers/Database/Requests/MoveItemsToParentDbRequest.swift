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
    let itemKeys: [String]
    let parentKey: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool {
        return true
    }

    func process(in database: Realm) throws {
        guard let parent = database.objects(RItem.self).filter(Predicates.key(self.parentKey, in: self.libraryId)).first else {
            return
        }

        database.objects(RItem.self)
                .filter(Predicates.keys(self.itemKeys, in: self.libraryId))
                .forEach { item in
                    item.parent = parent
                    item.changedFields.insert(.parent)
                }

        // Update the parent item, so that it's updated in the item list to show attachment/note marker
        let title = parent.title
        parent.title = title
    }
}
