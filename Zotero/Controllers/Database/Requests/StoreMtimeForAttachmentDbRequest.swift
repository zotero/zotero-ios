//
//  StoreMtimeForAttachmentDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 27.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct StoreMtimeForAttachmentDbRequest: DbRequest {
    let mtime: Int
    let key: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).uniqueObject(key: key, libraryId: libraryId),
              let field = item.fields.filter(.key(FieldKeys.Item.Attachment.mtime)).first else {
            throw DbError.objectNotFound
        }
        field.value = "\(self.mtime)"
        field.changed = true
        item.changes.append(RObjectChange.create(changes: RItemChanges.fields))
        item.changeType = .user
    }
}
