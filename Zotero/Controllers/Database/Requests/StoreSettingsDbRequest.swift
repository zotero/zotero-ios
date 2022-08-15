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

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        if let response = self.response.tagColors {
            self.syncTagColors(tags: response.value, in: database)
        }
        self.syncPages(pages: self.response.pageIndices.indices, in: database)
    }

    private func syncPages(pages: [PageIndexResponse], in database: Realm) {
        // Pages should be returned only by user library, just to be sure, let's ignore group sync
        switch self.libraryId {
        case .group: return
        case .custom: break
        }

        let indices = database.objects(RPageIndex.self).filter(.library(with: self.libraryId))

        pages.forEach { index in
            let rIndex: RPageIndex
            if let existing = indices.filter(.key(index.key)).first {
                rIndex = existing
            } else {
                rIndex = RPageIndex()
                database.add(rIndex)
                rIndex.key = index.key
                rIndex.libraryId = index.libraryId
            }
            rIndex.index = index.value
            rIndex.version = index.version
            rIndex.resetChanges()
        }
    }

    private func syncTagColors(tags: [TagColorResponse], in database: Realm) {
        let allTags = database.objects(RTag.self)
        tags.forEach { tag in
            if let existing = allTags.filter(.name(tag.name, in: self.libraryId)).first {
                if existing.color != tag.color {
                    existing.color = tag.color
                }
            } else {
                let new = RTag()
                new.name = tag.name
                new.color = tag.color
                new.libraryId = self.libraryId
                database.add(new)
            }
        }
    }
}
