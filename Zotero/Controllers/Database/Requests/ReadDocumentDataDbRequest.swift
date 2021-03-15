//
//  ReadDocumentDataDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 06.01.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadDocumentDataDbRequest: DbResponseRequest {
    typealias Response = Int

    let attachmentKey: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> Int {
        guard let pageIndex = database.objects(RPageIndex.self).filter(.key(self.attachmentKey, in: self.libraryId)).first else { return 0 }
        return pageIndex.index
    }
}
