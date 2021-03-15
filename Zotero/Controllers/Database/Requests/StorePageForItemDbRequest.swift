//
//  StorePageForItemDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 07.01.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct StorePageForItemDbRequest: DbRequest {

    let key: String
    let libraryId: LibraryIdentifier
    let page: Int

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        let pageIndex: RPageIndex

        if let existing = database.objects(RPageIndex.self).filter(.key(self.key, in: self.libraryId)).first {
            guard existing.index != self.page else { return }
            pageIndex = existing
        } else {
            pageIndex = RPageIndex()
            database.add(pageIndex)
            pageIndex.key = self.key
            pageIndex.libraryId = self.libraryId
        }

        pageIndex.index = self.page
        pageIndex.changedFields = .index
        pageIndex.changeType = .user
    }
}
