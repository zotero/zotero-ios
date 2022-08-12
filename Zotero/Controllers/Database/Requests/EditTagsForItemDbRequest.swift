//
//  EditTagsForItemDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 11.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct EditTagsForItemDbRequest: DbRequest {
    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    let key: String
    let libraryId: LibraryIdentifier
    let tags: [Tag]

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(self.key, in: self.libraryId)).first else { return }
        
        var tagsDidChange = false

        let tagsToRemove = item.tags.filter(.tagName(notIn: self.tags.map({ $0.name })))
        if !tagsToRemove.isEmpty {
            tagsDidChange = true
        }
        let baseTagsToRemove = (try? ReadBaseTagsToDeleteDbRequest(fromTags: tagsToRemove).process(in: database)) ?? []

        database.delete(tagsToRemove)
        if !baseTagsToRemove.isEmpty {
            database.delete(database.objects(RTag.self).filter(.name(in: baseTagsToRemove)))
        }

        let allTags = database.objects(RTag.self)

        for tag in self.tags {
            guard item.tags.filter(.tagName(tag.name)).first == nil else { continue }

            let rTag: RTag

            if let existing = allTags.filter(.name(tag.name, in: self.libraryId)).first {
                rTag = existing
            } else {
                rTag = RTag()
                rTag.name = tag.name
                rTag.color = tag.color
                rTag.libraryId = self.libraryId
                database.add(rTag)
            }

            let rTypedTag = RTypedTag()
            rTypedTag.type = .manual
            database.add(rTypedTag)

            rTypedTag.item = item
            rTypedTag.tag = rTag
            tagsDidChange = true
        }

        if tagsDidChange {
            // TMP: Temporary fix for Realm issue (https://github.com/realm/realm-core/issues/4994). Deletion of tag is not reported, so let's assign a value so that changes are visible in items list.
            item.rawType = item.rawType
            item.changeType = .user
            item.changedFields.insert(.tags)
        }
    }
}
