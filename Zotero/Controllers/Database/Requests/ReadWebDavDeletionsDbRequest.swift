//
//  ReadWebDavDeletionsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 29.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadWebDavDeletionsDbRequest: DbResponseRequest {
    typealias Response = Results<RWebDavDeletion>

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> Results<RWebDavDeletion> {
        return database.objects(RWebDavDeletion.self)
    }
}
