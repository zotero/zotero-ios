//
//  ReadItemDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 10/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadItemDbRequest: DbResponseRequest {
    typealias Response = RItem

    let libraryId: LibraryIdentifier
    let key: String

    var needsWrite: Bool { return false }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> RItem {
        guard let item = database.objects(RItem.self).filter(.key(self.key, in: self.libraryId)).first else {
            throw DbError.objectNotFound
        }
        return item
    }
}
