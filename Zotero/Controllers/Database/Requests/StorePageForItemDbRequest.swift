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
    let page: Int

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(self.key, in: self.libraryId)).first else { return }

        if let pageField = item.fields.filter(.key(FieldKeys.Item.Attachment.page)).first {
            guard Int(pageField.value) != self.page else { return }

            pageField.value = "\(self.page)"
            pageField.changed = true
            item.changedFields.insert(.fields)
            item.changeType = .user

            return
        }

        let pageField = RItemField()
        pageField.key = FieldKeys.Item.Attachment.page
        pageField.value = "\(self.page)"
        pageField.changed = true
        database.add(pageField)

        pageField.item = item
        item.changedFields.insert(.fields)
        item.changeType = .user
    }
}
