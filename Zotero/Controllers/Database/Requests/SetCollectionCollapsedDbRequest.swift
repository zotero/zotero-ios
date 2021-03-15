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
    let ignoreNotificationTokens: [NotificationToken]?

    func process(in database: Realm) throws {
        guard let collection = database.objects(RCollection.self).filter(.key(self.key, in: self.libraryId)).first, collection.collapsed != self.collapsed else { return }
        collection.collapsed = self.collapsed
    }
}
