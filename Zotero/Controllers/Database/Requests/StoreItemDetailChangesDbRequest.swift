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
    let fields: [NewItemDetailStore.StoreState.Field]
    let notes: [NewItemDetailStore.StoreState.Note]
    let attachments: [NewItemDetailStore.StoreState.Attachment]
    let tags: [NewItemDetailStore.StoreState.Tag]

    func process(in database: Realm) throws {
        let predicate = Predicates.key(self.itemKey, in: self.libraryId)
        guard let item = database.objects(RItem.self).filter(predicate).first else { return }

        var fieldsDidChange = false

        // Update item type

        if let type = self.type {
            // If type changed, we need to sync all fields, since different types can have different fields
            item.rawType = type
            item.changedFields.insert(.type)

            // Remove fields that don't exist in this new type
            let fieldKeys = self.fields.map({ $0.key })
            let toRemove = item.fields.filter(Predicates.key(notIn: fieldKeys))
            database.delete(toRemove)
            fieldsDidChange = !toRemove.isEmpty
        }

        // Update fields

        for field in self.fields {
            // Either type changed and we're updating all fields (so that we create missing fields for this new type)
            // or type didn't change and we're updating only changed fields
            guard self.type != nil || field.changed else { continue }

            if let existing = item.fields.filter(Predicates.key(field.key)).first {
                if field.changed {
                    existing.value = field.value
                    existing.changed = true

                    if field.isTitle {
                        item.title = field.value
                    }
                }
            } else {
                let rField = RItemField()
                rField.key = field.key
                rField.value = field.value
                rField.changed = field.changed
                rField.item = item
                database.add(rField)

                item.title = field.value
            }
        }

        if fieldsDidChange {
            item.changedFields.insert(.fields)
        }

        // Update notes

        let noteKeys = self.notes.map({ $0.key })
        let notesToRemove = item.children.filter(Predicates.item(type: ItemTypes.note))
                                         .filter(Predicates.key(notIn: noteKeys))
        notesToRemove.forEach {
            $0.trash = true
            $0.changedFields.insert(.trash)
        }

        for note in self.notes {
            guard note.changed else { continue }

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

        let attachmentKeys = self.attachments.map({ $0.key })
        let attachmentsToRemove = item.children.filter(Predicates.item(type: ItemTypes.attachment))
                                               .filter(Predicates.key(notIn: attachmentKeys))
        attachmentsToRemove.forEach {
            $0.trash = true
            $0.changedFields.insert(.trash)
            // TODO: - check if files need to be deleted
        }

        for attachment in self.attachments {
            guard attachment.changed else { continue }

            if let childItem = item.children.filter(Predicates.key(attachment.key)).first,
               let titleField = childItem.fields.filter(Predicates.key(FieldKeys.title)).first {
                guard titleField.value != attachment.title else { continue }
                // Only title can change for attachment, if you want to change the file you have to delete the old
                // and create a new attachment
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

        let tagNames = self.tags.map({ $0.name })
        let tagsToRemove = item.tags.filter(Predicates.name(notIn: tagNames))
        tagsToRemove.forEach { tag in
            if let index = tag.items.index(of: item) {
                tag.items.remove(at: index)
            }
            tagsDidChange = true
        }

        self.tags.forEach { tag in
            if let rTag = database.objects(RTag.self).filter(Predicates.name(tag.name, in: self.libraryId))
                                                     .filter("not (any items.key = %@)", self.itemKey).first {
                rTag.items.append(item)
                tagsDidChange = true
            }
        }

        if tagsDidChange {
            item.changedFields.insert(.tags)
        }
    }
}
