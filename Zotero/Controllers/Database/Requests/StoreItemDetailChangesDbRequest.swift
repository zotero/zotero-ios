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
    let data: ItemDetailStore.State.Data
    let snapshot: ItemDetailStore.State.Data
    let schemaController: SchemaController

    func process(in database: Realm) throws {
        let predicate = Predicates.key(self.itemKey, in: self.libraryId)
        guard let item = database.objects(RItem.self).filter(predicate).first else { return }

        let allFields = self.data.allFields(schemaController: self.schemaController)

        var fieldsDidChange = false
        var typeChanged = false

        // Update item type

        if self.data.type != item.rawType {
            // If type changed, we need to sync all fields, since different types can have different fields
            item.rawType = self.data.type
            item.changedFields.insert(.type)

            // Remove fields that don't exist in this new type
            let fieldKeys = allFields.map({ $0.key })
            let toRemove = item.fields.filter(Predicates.key(notIn: fieldKeys))
            database.delete(toRemove)

            fieldsDidChange = !toRemove.isEmpty
            typeChanged = true
        }

        // Update fields

        let snapshotFields = self.snapshot.allFields(schemaController: self.schemaController)

        for (offset, field) in allFields.enumerated() {
            // Either type changed and we're updating all fields (so that we create missing fields for this new type)
            // or type didn't change and we're updating only changed fields
            guard typeChanged || (field.value != snapshotFields[offset].value) else { continue }

            if let existing = item.fields.filter(Predicates.key(field.key)).first {
                if field.value != existing.value {
                    existing.value = field.value
                    existing.changed = true

                    if field.isTitle {
                        item.title = field.value
                    }

                    fieldsDidChange = true
                }
            } else {
                let rField = RItemField()
                rField.key = field.key
                rField.value = field.value
                rField.changed = true
                rField.item = item
                database.add(rField)

                item.title = field.value
                fieldsDidChange = true
            }
        }

        if fieldsDidChange {
            item.changedFields.insert(.fields)
        }

        // Update notes

        let noteKeys = self.data.notes.map({ $0.key })
        let notesToRemove = item.children.filter(Predicates.item(type: ItemTypes.note))
                                         .filter(Predicates.key(notIn: noteKeys))
        notesToRemove.forEach {
            $0.trash = true
            $0.changedFields.insert(.trash)
        }

        for note in self.data.notes {
            guard note.text != self.snapshot.notes.first(where: { $0.key == note.key })?.text else { continue }

            if let childItem = item.children.filter(Predicates.key(note.key)).first,
               let noteField = childItem.fields.filter(Predicates.key(FieldKeys.note)).first {
                guard noteField.value != note.text else { continue }
                childItem.title = note.title
                childItem.changedFields.insert(.fields)
                noteField.value = note.text
                noteField.changed = true
            } else {
                let childItem = try CreateNoteDbRequest(note: note).process(in: database)
                childItem.parent = item
                childItem.libraryObject = item.libraryObject
                childItem.changedFields.insert(.parent)
            }
        }

        // Update attachments

        let attachmentKeys = self.data.attachments.map({ $0.key })
        let attachmentsToRemove = item.children.filter(Predicates.item(type: ItemTypes.attachment))
                                               .filter(Predicates.key(notIn: attachmentKeys))
        attachmentsToRemove.forEach {
            $0.trash = true
            $0.changedFields.insert(.trash)
            // TODO: - check if files need to be deleted
        }

        for attachment in self.data.attachments {
            // Only title can change for attachment, if you want to change the file you have to delete the old
            // and create a new attachment
            guard attachment.title != self.snapshot.attachments.first(where: { $0.key == attachment.key })?.title else { continue }

            if let childItem = item.children.filter(Predicates.key(attachment.key)).first,
               let titleField = childItem.fields.filter(Predicates.key(FieldKeys.title)).first {
                guard titleField.value != attachment.title else { continue }
                childItem.title = attachment.title
                childItem.changedFields.insert(.fields)
                titleField.value = attachment.title
                titleField.changed = true
            } else {
                let childItem = try CreateAttachmentDbRequest(attachment: attachment).process(in: database)
                childItem.libraryObject = item.libraryObject
                childItem.parent = item
                childItem.changedFields.insert(.parent)
            }
        }

        // Update tags

        var tagsDidChange = false

        let tagNames = self.data.tags.map({ $0.name })
        let tagsToRemove = item.tags.filter(Predicates.name(notIn: tagNames))
        tagsToRemove.forEach { tag in
            if let index = tag.items.index(of: item) {
                tag.items.remove(at: index)
            }
            tagsDidChange = true
        }

        self.data.tags.forEach { tag in
            if let rTag = database.objects(RTag.self).filter(Predicates.name(tag.name, in: self.libraryId))
                                                     .filter("not (any items.key = %@)", self.itemKey).first {
                rTag.items.append(item)
                tagsDidChange = true
            }
        }

        if tagsDidChange {
            item.changedFields.insert(.tags)
        }

        // Update creators

        if self.data.creators != self.snapshot.creators {
            database.delete(item.creators)

            self.data.creators.enumerated().forEach { (offset, creator) in
                let rCreator = RCreator()
                rCreator.rawType = creator.type
                rCreator.firstName = creator.firstName
                rCreator.lastName = creator.lastName
                rCreator.name = creator.fullName
                rCreator.orderId = offset
                rCreator.item = item
                database.add(rCreator)
            }

            item.changedFields.insert(.creators)
        }
    }
}
