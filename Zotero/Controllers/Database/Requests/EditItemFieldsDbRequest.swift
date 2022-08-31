//
//  EditItemFieldsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 31.08.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct EditItemFieldsDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier
    let fieldValues: [KeyBaseKeyPair: String]

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(self.key, in: self.libraryId)).first else { return }

        var didChange = false

        for field in item.fields {
            // Fix existing items to be compatible with `annotationPosition` stored in `baseKey`.
            switch field.key {
            case FieldKeys.Item.Annotation.Position.pageIndex where field.baseKey == nil,
                 FieldKeys.Item.Annotation.Position.lineWidth where field.baseKey == nil:
                // If there is just one key which is missing the `baseKey`, assign `annotationPosition` to it. If there are duplicates, it must be a new item and `baseKey` should be assigned properly.
                if item.fields.filter(.key(field.key)).count == 1 {
                    field.baseKey = FieldKeys.Item.Annotation.position
                }

            default: break
            }

            let keyPair = KeyBaseKeyPair(key: field.key, baseKey: field.baseKey)
            if let value = self.fieldValues[keyPair], field.value != value {
                field.value = value
                field.changed = true
                didChange = true
            }
        }

        if didChange {
            item.changedFields.insert(.fields)
            item.changeType = .user
        }
    }
}
