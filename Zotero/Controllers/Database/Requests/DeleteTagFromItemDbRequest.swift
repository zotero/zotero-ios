//
//  DeleteTagFromItemDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 11.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct DeleteTagFromItemDbRequest: DbRequest {
    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    let key: String
    let libraryId: LibraryIdentifier
    let tagName: String

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(self.key, in: self.libraryId)).first else { return }

        let tagsToRemove = item.tags.filter(.tagName(self.tagName))

        guard !tagsToRemove.isEmpty else { return }

        let baseTagsToRemove = (try? ReadBaseTagsToDeleteDbRequest(fromTags: tagsToRemove).process(in: database)) ?? []

        database.delete(tagsToRemove)
        
        if !baseTagsToRemove.isEmpty {
            database.delete(database.objects(RTag.self).filter(.name(in: baseTagsToRemove)))
        }

        // TMP: Temporary fix for Realm issue (https://github.com/realm/realm-core/issues/4994). Deletion of tag is not reported, so let's assign a value so that changes are visible in items list.
        item.rawType = item.rawType
        item.changeType = .user
        item.changedFields.insert(.tags)
    }
}
