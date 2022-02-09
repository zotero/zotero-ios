//
//  SetCollectionCollapsedDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 15.03.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct SetCollectionCollapsedDbRequest: DbRequest {
    let collapsed: Bool
    let key: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        guard let collection = database.objects(RCollection.self).filter(.key(self.key, in: self.libraryId)).first, collection.collapsed != self.collapsed else { return }
        collection.collapsed = self.collapsed
    }
}

struct SetCollectionsCollapsedDbRequest: DbRequest {
    let keys: Set<String>
    let collapsed: Bool
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        for collection in database.objects(RCollection.self).filter(.keys(self.keys, in: self.libraryId)) {
            collection.collapsed = self.collapsed
        }
    }
}
