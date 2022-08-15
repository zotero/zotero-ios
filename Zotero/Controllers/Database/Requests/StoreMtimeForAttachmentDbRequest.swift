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
        guard let item = database.objects(RItem.self).filter(.key(self.key, in: self.libraryId)).first,
              let field = item.fields.filter(.key(FieldKeys.Item.Attachment.mtime)).first else {
            throw DbError.objectNotFound
        }
        field.value = "\(self.mtime)"
        field.changed = true
        item.changedFields.insert(.fields)
        item.changeType = .user
    }
}
