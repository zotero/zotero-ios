//
//  DeleteFailedItemsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 03.04.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct DeleteFailedItemsDbRequest: DbRequest {
    var needsWrite: Bool { return true }

    let key: String
    let libraryId: LibraryIdentifier

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(key, in: libraryId)).first else { return }
        deleteItemAndChildrenAsNeeded(item: item, in: database)
    }

    private func deleteItemAndChildrenAsNeeded(item: RItem, in database: Realm) {
        if !item.changes.isEmpty {
            // Item did not sync yet, delete with children
            item.willRemove(in: database)
            database.delete(item)
            return
        }

        // Item synced, mark for deletion and check children.
        item.deleted = true
        item.changeType = .user

        for child in item.children {
            deleteItemAndChildrenAsNeeded(item: child, in: database)
        }
    }
}
