//
//  AssignItemsToCollectionsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 11/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct AssignItemsToCollectionsDbRequest: DbRequest {
    let collectionKeys: Set<String>
    let itemKeys: Set<String>
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        let collections = database.objects(RCollection.self).filter(.keys(self.collectionKeys, in: self.libraryId))
        let items = database.objects(RItem.self).filter(.keys(self.itemKeys, in: self.libraryId))
        collections.forEach { collection in
            items.forEach { item in
                if !collection.items.contains(item) {
                    collection.items.append(item)
                    item.changedFields.insert(.collections)
                    item.changeType = .user
                }
            }
        }
    }
}
