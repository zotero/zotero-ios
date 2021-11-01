//
//  DeleteWebDavDeletionsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 29.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct DeleteWebDavDeletionsDbRequest: DbRequest {
    let keys: Set<String>
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        database.delete(database.objects(RWebDavDeletion.self).filter(.keys(self.keys, in: self.libraryId)))
    }
}
