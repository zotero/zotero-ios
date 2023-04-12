//
//  AddTagsToItemDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 11.04.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct AddTagsToItemDbRequest: DbRequest {
    var needsWrite: Bool { return true }

    let key: String
    let libraryId: LibraryIdentifier
    let tagNames: Set<String>

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(self.key, in: self.libraryId)).first else { return }

        var toAdd: Set<String> = self.tagNames

        for tag in item.tags {
            if let name = tag.tag?.name, self.tagNames.contains(name) {
                toAdd.remove(name)
            }
        }

        guard !toAdd.isEmpty else { return }

        let allTags = database.objects(RTag.self)

        for name in toAdd {
            guard let rTag = allTags.filter(.name(name)).first else { continue }

            let rTypedTag = RTypedTag()
            rTypedTag.type = .manual
            database.add(rTypedTag)

            rTypedTag.item = item
            rTypedTag.tag = rTag
        }

        // TMP: Temporary fix for Realm issue (https://github.com/realm/realm-core/issues/4994). Deletion of tag is not reported, so let's assign a value so that changes are visible in items list.
        item.rawType = item.rawType
        item.changeType = .user
        item.changes.append(RObjectChange.create(changes: RItemChanges.tags))
    }
}
