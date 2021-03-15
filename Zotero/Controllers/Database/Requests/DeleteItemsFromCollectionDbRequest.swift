//
//  DeleteItemsFromCollectionDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 22/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct DeleteItemsFromCollectionDbRequest: DbRequest {
    let collectionKey: String
    let itemKeys: Set<String>
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        guard let collection = database.objects(RCollection.self)
                                       .filter(.key(self.collectionKey, in: self.libraryId)).first else {
            return
        }
        let items = database.objects(RItem.self).filter(.keys(self.itemKeys, in: self.libraryId))

        items.forEach { item in
            if let index = collection.items.index(of: item) {
                collection.items.remove(at: index)
                item.changedFields.insert(.collections)
                item.changeType = .user
            }
        }
    }
}
