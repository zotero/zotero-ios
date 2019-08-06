//
//  StoreItemDetailChangesDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 25/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack
import RealmSwift

struct StoreItemDetailChangesDbRequest: DbRequest {
    var needsWrite: Bool {
        return true
    }

    let libraryId: LibraryIdentifier
    let itemKey: String
    let type: String?
    let title: String?
    let abstract: String?
    let fields: [ItemDetailStore.StoreState.Field]
    let notes: [ItemDetailStore.StoreState.Note]
    let attachments: [ItemDetailStore.StoreState.Attachment]
    let tags: [ItemDetailStore.StoreState.Tag]
    let allFields: [FieldSchema]

    func process(in database: Realm) throws {
        let predicate = Predicates.key(self.itemKey, in: self.libraryId)
        guard let item = database.objects(RItem.self).filter(predicate).first else { return }

        var fieldsDidChange = false

        if let type = self.type {
            item.rawType = type
            item.changedFields.insert(.type)

            // If type changed, we need to sync all fields, since different types can have different fields

            // Remove fields that don't exist in this new type
            let fieldKeys = self.allFields.map({ $0.field })
            let toRemove = item.fields.filter("key not in %@", fieldKeys)
            database.delete(toRemove)

            self.allFields.forEach { field in
                let rField: RItemField
                if let existing = item.fields.filter(Predicates.key(field.field)).first {
                    rField = existing
                } else {
                    rField = RItemField()
                    rField.key = field.field
                    rField.item = item
                    database.add(rField)
                }

                if let field = self.fields.first(where: { $0.key == field.field }), field.changed {
                    rField.value = field.value
                    rField.changed = true
                    fieldsDidChange = true
                }
            }
        } else {
            // If type didn't change, we change just updated existing fields
            for field in self.fields {
                guard field.changed,
                      let itemField = item.fields.filter(Predicates.key(field.key)).first else { continue }
                itemField.value = field.value
                itemField.changed = true
                fieldsDidChange = true
            }
        }

        if let title = self.title {
            item.title = title
            if let titleKey = self.allFields.first(where: { $0.field == FieldKeys.title ||
                                                            $0.baseField == FieldKeys.title })?.field,
               let field = item.fields.filter(Predicates.key(titleKey)).first {
                field.value = title
                field.changed = true
            }
            fieldsDidChange = true
        }

        if let abstract = self.abstract,
           let abstractField = item.fields.filter(Predicates.key(FieldKeys.abstract)).first {
            abstractField.value = abstract
            abstractField.changed = true
            fieldsDidChange = true
        }

        if fieldsDidChange {
            item.changedFields.insert(.fields)
        }

        // TODO: - remove notes that were deleted

        for note in self.notes {
            guard note.changed else { continue }

            if let childItem = item.children.filter(Predicates.key(note.key)).first,
               let noteField = childItem.fields.filter(Predicates.key(FieldKeys.note)).first {
                childItem.changedFields.insert(.fields)
                childItem.title = note.title
                noteField.value = note.text
                noteField.changed = true
            } else {
                let childItem = RItem()
                childItem.key = KeyGenerator.newKey
                childItem.rawType = FieldKeys.note
                childItem.syncState = .synced
                childItem.title = note.title
                childItem.changedFields = [.fields, .type, .parent]
                childItem.libraryObject = item.libraryObject
                childItem.parent = item
                childItem.dateAdded = Date()
                childItem.dateModified = Date()
                database.add(childItem)

                let noteField = RItemField()
                noteField.key = FieldKeys.note
                noteField.value = note.text
                noteField.changed = true
                noteField.item = childItem
                database.add(noteField)
            }
        }

        // TODO: sync attachments, sync tags
    }
}
