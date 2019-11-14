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
        guard let item = database.objects(RItem.self).filter(.key(self.itemKey, in: self.libraryId)).first else { return }

        let typeChanged = self.data.type != item.rawType
        if typeChanged {
            item.rawType = self.data.type
            item.changedFields.insert(.type)
        }
        item.dateModified = self.data.dateModified

        self.updateCreators(with: self.data, snapshot: self.snapshot, item: item, database: database)
        self.updateFields(with: self.data, snapshot: self.snapshot, item: item, typeChanged: typeChanged, database: database)
        try self.updateNotes(with: self.data, snapshot: self.snapshot, item: item, database: database)
        try self.updateAttachments(with: self.data, snapshot: self.snapshot, item: item, database: database)
        self.updateTags(with: self.data, item: item, database: database)

        // Item title depends on item type, creators and fields, so we update derived titles (displayTitle and sortTitle) after everything else synced
        item.updateDerivedTitles()
    }

    private func updateCreators(with data: ItemDetailStore.State.Data, snapshot: ItemDetailStore.State.Data, item: RItem, database: Realm) {
        guard data.creators != snapshot.creators else { return }

        database.delete(item.creators)

        for (offset, creatorId) in data.creatorIds.enumerated() {
            guard let creator = data.creators[creatorId] else { continue }

            let rCreator = RCreator()
            rCreator.rawType = creator.type
            rCreator.firstName = creator.firstName
            rCreator.lastName = creator.lastName
            rCreator.name = creator.fullName
            rCreator.orderId = offset
            rCreator.primary = creator.primary
            rCreator.item = item
            database.add(rCreator)
        }

        item.updateCreatorSummary()
        item.changedFields.insert(.creators)
    }

    private func updateFields(with data: ItemDetailStore.State.Data, snapshot: ItemDetailStore.State.Data,
                              item: RItem, typeChanged: Bool, database: Realm) {
        let allFields = self.data.databaseFields(schemaController: self.schemaController)
        let snapshotFields = self.snapshot.databaseFields(schemaController: self.schemaController)

        var fieldsDidChange = false

        if typeChanged {
            // If type changed, we need to sync all fields, since different types can have different fields
            let fieldKeys = allFields.map({ $0.key })
            let toRemove = item.fields.filter(.key(notIn: fieldKeys))

            toRemove.forEach { field in
                if field.key == FieldKeys.date {
                    item.setDateFieldMetadata(nil)
                } else if field.key == FieldKeys.publisher || field.baseKey == FieldKeys.publisher {
                    item.publisher = nil
                    item.hasPublisher = false
                } else if field.key == FieldKeys.publicationTitle || field.baseKey == FieldKeys.publicationTitle {
                    item.publicationTitle = nil
                    item.hasPublicationTitle = false
                }
            }

            database.delete(toRemove)

            fieldsDidChange = !toRemove.isEmpty
        }

        for (offset, field) in allFields.enumerated() {
            // Either type changed and we're updating all fields (so that we create missing fields for this new type)
            // or type didn't change and we're updating only changed fields
            guard typeChanged || (field.value != snapshotFields[offset].value) else { continue }

            var fieldToChange: RItemField?

            if let existing = item.fields.filter(.key(field.key)).first {
                fieldToChange = (field.value != existing.value) ? existing : nil
            } else {
                let rField = RItemField()
                rField.key = field.key
                rField.baseKey = field.baseField
                rField.item = item
                database.add(rField)
                fieldToChange = rField
            }

            if let rField = fieldToChange {
                rField.value = field.value
                rField.changed = true

                if field.isTitle {
                    item.baseTitle = field.value
                } else if field.key == FieldKeys.date {
                    item.setDateFieldMetadata(field.value)
                } else if field.key == FieldKeys.publisher || field.baseField == FieldKeys.publisher {
                    item.publisher = field.value
                    item.hasPublisher = !field.value.isEmpty
                } else if field.key == FieldKeys.publicationTitle || field.baseField == FieldKeys.publicationTitle {
                    item.publicationTitle = field.value
                    item.hasPublicationTitle = !field.value.isEmpty
                }

                fieldsDidChange = true
            }
        }

        if fieldsDidChange {
            item.changedFields.insert(.fields)
        }
    }

    private func updateNotes(with data: ItemDetailStore.State.Data, snapshot: ItemDetailStore.State.Data, item: RItem, database: Realm) throws {
        let noteKeys = data.notes.map({ $0.key })
        let notesToRemove = item.children.filter(.item(type: ItemTypes.note))
                                         .filter(.key(notIn: noteKeys))
        notesToRemove.forEach {
            $0.trash = true
            $0.changedFields.insert(.trash)
        }

        for note in data.notes {
            guard note.text != snapshot.notes.first(where: { $0.key == note.key })?.text else { continue }

            if let childItem = item.children.filter(.key(note.key)).first,
               let noteField = childItem.fields.filter(.key(FieldKeys.note)).first {
                guard noteField.value != note.text else { continue }
                childItem.setTitle(note.title)
                childItem.changedFields.insert(.fields)
                noteField.value = note.text
                noteField.changed = true
            } else {
                let childItem = try CreateNoteDbRequest(note: note,
                                                        localizedType: (self.schemaController.localized(itemType: ItemTypes.note) ?? ""),
                                                        libraryId: nil).process(in: database)
                childItem.parent = item
                childItem.libraryObject = item.libraryObject
                childItem.changedFields.insert(.parent)
            }
        }
    }

    private func updateAttachments(with data: ItemDetailStore.State.Data, snapshot: ItemDetailStore.State.Data, item: RItem, database: Realm) throws {
        let attachmentKeys = data.attachments.map({ $0.key })
        let attachmentsToRemove = item.children.filter(.item(type: ItemTypes.attachment))
                                               .filter(.key(notIn: attachmentKeys))
        attachmentsToRemove.forEach {
            $0.trash = true
            $0.changedFields.insert(.trash)
            // TODO: - check if files need to be deleted
        }

        for attachment in data.attachments {
            // Only title can change for attachment, if you want to change the file you have to delete the old
            // and create a new attachment
            guard attachment.title != snapshot.attachments.first(where: { $0.key == attachment.key })?.title else { continue }

            if let childItem = item.children.filter(.key(attachment.key)).first,
               let titleField = childItem.fields.filter(.key(FieldKeys.title)).first {
                guard titleField.value != attachment.title else { continue }
                childItem.setTitle(attachment.title)
                childItem.changedFields.insert(.fields)
                titleField.value = attachment.title
                titleField.changed = true
            } else {
                let childItem = try CreateAttachmentDbRequest(attachment: attachment,
                                                              localizedType: (self.schemaController.localized(itemType: ItemTypes.attachment) ?? ""),
                                                              libraryId: nil).process(in: database)
                childItem.libraryObject = item.libraryObject
                childItem.parent = item
                childItem.changedFields.insert(.parent)
            }
        }
    }

    private func updateTags(with data: ItemDetailStore.State.Data, item: RItem, database: Realm) {
        var tagsDidChange = false

        let tagNames = data.tags.map({ $0.name })
        let tagsToRemove = item.tags.filter(.name(notIn: tagNames))
        tagsToRemove.forEach { tag in
            if let index = tag.items.index(of: item) {
                tag.items.remove(at: index)
            }
            tagsDidChange = true
        }

        data.tags.forEach { tag in
            if let rTag = database.objects(RTag.self).filter(.name(tag.name, in: self.libraryId))
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
