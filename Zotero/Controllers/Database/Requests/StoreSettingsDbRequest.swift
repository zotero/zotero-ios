//
//  StoreSettingsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 26/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct StoreSettingsDbRequest: DbRequest {
    let response: SettingsResponse
    let libraryId: LibraryIdentifier

    var needsWrite: Bool {
        return true
    }

    func process(in database: Realm) throws {
        if let response = self.response.tagColors {
            self.syncTags(tags: response.value, in: database)
        }
        self.syncPages(pages: self.response.pageIndices.indices, in: database)
    }

    private func syncPages(pages: [PageIndexResponse], in database: Realm) {
        let indices = database.objects(RPageIndex.self).filter(.library(with: self.libraryId))

        pages.forEach { index in
            let rIndex: RPageIndex
            if let existing = indices.filter(.key(index.key)).first {
                rIndex = existing
            } else {
                rIndex = RPageIndex()
                database.add(rIndex)
                rIndex.key = index.key
                rIndex.libraryId = self.libraryId
            }
            rIndex.index = index.value
            rIndex.version = index.version
            rIndex.resetChanges()
        }
    }

    private func syncTags(tags: [TagColorResponse], in database: Realm) {
        let allTags = database.objects(RTag.self)

        tags.forEach { tag in
            let rTag: RTag
            if let existing = allTags.filter(.name(tag.name, in: self.libraryId)).first {
                rTag = existing
            } else {
                rTag = RTag()
                database.add(rTag)
                rTag.name = tag.name
                rTag.libraryId = self.libraryId
            }
            rTag.color = tag.color
        }
    }
}
