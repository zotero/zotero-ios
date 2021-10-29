//
//  CreateWebDavDeletionsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 29.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct CreateWebDavDeletionsDbRequest: DbRequest {
    let keys: [String]
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        // Create web dav deletion only for attachment items.
        let items = database.objects(RItem.self).filter(.keys(self.keys, in: self.libraryId)).filter(.item(type: ItemTypes.attachment))
        for item in items {
            let deletion = RWebDavDeletion()
            deletion.key = item.key
            deletion.libraryId = self.libraryId
            database.add(deletion)
        }
    }
}
