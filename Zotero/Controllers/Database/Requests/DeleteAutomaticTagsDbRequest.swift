//
//  DeleteAutomaticTagsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 05.04.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct DeleteAutomaticTagsDbRequest: DbRequest {
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let typedTags = try ReadAutomaticTagsDbRequest(libraryId: self.libraryId).process(in: database)

        let date = Date()
        for tag in typedTags {
            guard let item = tag.item else { continue }
            item.changes.append(RObjectChange.create(changes: RItemChanges.tags))
            item.dateModified = date
            tag.item = nil
        }
        database.delete(typedTags)

        let tags = database.objects(RTag.self).filter(.library(with: self.libraryId))
                                              .filter("color = \"\"")
                                              .filter("tags.@count = 0")
        database.delete(tags)
    }
}

