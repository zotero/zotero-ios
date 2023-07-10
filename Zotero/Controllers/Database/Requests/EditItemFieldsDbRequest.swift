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
        guard !self.fieldValues.isEmpty, let item = database.objects(RItem.self).filter(.key(self.key, in: self.libraryId)).first else { return }

        var didChange = false

        for data in self.fieldValues {
            let filter: NSPredicate = data.key.baseKey.flatMap({ .key(data.key.key, andBaseKey: $0) }) ?? .key(data.key.key)

            guard let field = item.fields.filter(filter).first, data.value != field.value else { continue }

            field.value = data.value
            field.changed = true
            didChange = true

            switch field.key {
            case FieldKeys.Item.note, FieldKeys.Item.Annotation.comment:
                item.htmlFreeContent = data.value.isEmpty ? nil : data.value.strippedHtmlTags

            default:
                break
            }
        }

        if didChange {
            item.changes.append(RObjectChange.create(changes: RItemChanges.fields))
            item.changeType = .user
        }
    }
}
