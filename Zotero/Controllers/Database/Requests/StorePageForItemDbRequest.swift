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
    let page: String

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let pageIndex: RPageIndex

        if let existing = database.objects(RPageIndex.self).uniqueObject(key: key, libraryId: libraryId) {
            guard existing.index != self.page else { return }
            pageIndex = existing
        } else {
            pageIndex = RPageIndex()
            database.add(pageIndex)
            pageIndex.key = self.key
            pageIndex.libraryId = self.libraryId
        }

        pageIndex.index = self.page
        pageIndex.changes.append(RObjectChange.create(changes: RPageIndexChanges.index))
        pageIndex.changeType = .user
    }
}
