//
//  ReadTagsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 09/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadTagsDbRequest: DbResponseRequest {
    typealias Response = [Tag]

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> [Tag] {
        return database.objects(RTag.self).filter(.library(with: self.libraryId))
                                          .sorted(byKeyPath: "name")
                                          .map(Tag.init)
    }
}
