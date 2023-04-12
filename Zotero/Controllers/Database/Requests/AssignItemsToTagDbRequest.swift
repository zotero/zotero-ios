//
//  AssignItemsToTagDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 12.04.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct AssignItemsToTagDbRequest: DbRequest {
    var needsWrite: Bool { return true }

    let keys: Set<String>
    let libraryId: LibraryIdentifier
    let tagName: String

    func process(in database: Realm) throws {
        guard let tag = database.objects(RTag.self).filter(.name(self.tagName)).first else { return }

        let items = database.objects(RItem.self).filter(.keys(self.keys, in: self.libraryId))
        for item in items {
            guard item.tags.filter("tag.name == %@", self.tagName).first == nil else { continue }

            let rTypedTag = RTypedTag()
            rTypedTag.type = .manual
            database.add(rTypedTag)

            rTypedTag.item = item
            rTypedTag.tag = tag

            // TMP: Temporary fix for Realm issue (https://github.com/realm/realm-core/issues/4994). Deletion of tag is not reported, so let's assign a value so that changes are visible in items list.
            item.rawType = item.rawType
            item.changeType = .user
            item.changes.append(RObjectChange.create(changes: RItemChanges.tags))
        }
    }
}
