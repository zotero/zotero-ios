//
//  EditItemDetailDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 25/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct EditItemDetailDbRequest: DbRequest {
    var needsWrite: Bool {
        return true
    }

    let libraryId: LibraryIdentifier
    let itemKey: String
    let data: ItemDetailState.Data
    let snapshot: ItemDetailState.Data
    let schemaController: SchemaController
    let dateParser: DateParser

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
        item.changeType = .user
    }

    private func updateCreators(with data: ItemDetailState.Data, snapshot: ItemDetailState.Data, item: RItem, database: Realm) {
        guard data.creators != snapshot.creators else { return }

        database.delete(item.creators)

        for (offset, creatorId) in data.creatorIds.enumerated() {
            guard let creator = data.creators[creatorId] else { continue }

            let rCreator = RCreator()
            rCreator.rawType = creator.type
            rCreator.orderId = offset
            rCreator.primary = creator.primary
            rCreator.item = item

            switch creator.namePresentation {
            case .full:
                rCreator.name = creator.fullName
                rCreator.firstName = ""
                rCreator.lastName = ""
            case .separate:
                rCreator.name = ""
                rCreator.firstName = creator.firstName
                rCreator.lastName = creator.lastName
            }

            database.add(rCreator)
        }

        item.updateCreatorSummary()
        item.changedFields.insert(.creators)
    }

    private func updateFields(with data: ItemDetailState.Data, snapshot: ItemDetailState.Data,
                              item: RItem, typeChanged: Bool, database: Realm) {
        let allFields = self.data.databaseFields(schemaController: self.schemaController)
        let snapshotFields = self.snapshot.databaseFields(schemaController: self.schemaController)

        var fieldsDidChange = false

        if typeChanged {
            // If type changed, we need to sync all fields, since different types can have different fields
            let fieldKeys = allFields.map({ $0.key })
            let toRemove = item.fields.filter(.key(notIn: fieldKeys))

            toRemove.forEach { field in
                if field.key == FieldKeys.Item.date {
                    item.setDateFieldMetadata(nil, parser: self.dateParser)
                } else if field.key == FieldKeys.Item.publisher || field.baseKey == FieldKeys.Item.publisher {
                    item.set(publisher: nil)
                } else if field.key == FieldKeys.Item.publicationTitle || field.baseKey == FieldKeys.Item.publicationTitle {
                    item.set(publicationTitle: nil)
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
                } else if field.key == FieldKeys.Item.date {
                    item.setDateFieldMetadata(field.value, parser: self.dateParser)
                } else if field.key == FieldKeys.Item.publisher || field.baseField == FieldKeys.Item.publisher {
                    item.set(publisher: field.value)
                } else if field.key == FieldKeys.Item.publicationTitle || field.baseField == FieldKeys.Item.publicationTitle {
                    item.set(publicationTitle: field.value)
                }

                fieldsDidChange = true
            }
        }

        if fieldsDidChange {
            item.changedFields.insert(.fields)
        }
    }

    private func updateNotes(with data: ItemDetailState.Data, snapshot: ItemDetailState.Data, item: RItem, database: Realm) throws {
        let notesToRemove = item.children.filter(.item(type: ItemTypes.note))
                                         .filter(.key(in: data.deletedNotes))
        notesToRemove.forEach {
            $0.trash = true
            $0.changedFields.insert(.trash)
        }

        for note in data.notes {
            guard note.text != snapshot.notes.first(where: { $0.key == note.key })?.text else { continue }

            if let childItem = item.children.filter(.key(note.key)).first,
               let noteField = childItem.fields.filter(.key(FieldKeys.Item.note)).first {
                guard noteField.value != note.text else { continue }
                childItem.set(title: note.title)
                childItem.changedFields.insert(.fields)
                noteField.value = note.text
                noteField.changed = true
            } else {
                let childItem = try CreateNoteDbRequest(note: note,
                                                        localizedType: (self.schemaController.localized(itemType: ItemTypes.note) ?? ""),
                                                        libraryId: self.libraryId,
                                                        collectionKey: nil).process(in: database)
                childItem.parent = item
                childItem.changedFields.insert(.parent)
            }
        }
    }

    private func updateAttachments(with data: ItemDetailState.Data, snapshot: ItemDetailState.Data, item: RItem, database: Realm) throws {
        let attachmentsToRemove = item.children.filter(.item(type: ItemTypes.attachment))
                                               .filter(.key(in: data.deletedAttachments))
        var hasMainAttachmentChange = false

        attachmentsToRemove.forEach {
            $0.trash = true
            $0.changedFields.insert(.trash)

            if !hasMainAttachmentChange {
                hasMainAttachmentChange = $0.key == item.mainAttachment?.key
            }
        }

        for attachment in data.attachments {
            // Only title can change for attachment, if you want to change the file you have to delete the old
            // and create a new attachment
            guard attachment.title != snapshot.attachments.first(where: { $0.key == attachment.key })?.title else { continue }

            if let childItem = item.children.filter(.key(attachment.key)).first,
               let titleField = childItem.fields.filter(.key(FieldKeys.Item.title)).first {
                guard titleField.value != attachment.title else { continue }
                childItem.set(title: attachment.title)
                childItem.changedFields.insert(.fields)
                titleField.value = attachment.title
                titleField.changed = true
            } else {
                let childItem = try CreateAttachmentDbRequest(attachment: attachment,
                                                              localizedType: (self.schemaController.localized(itemType: ItemTypes.attachment) ?? ""),
                                                              collections: []).process(in: database)
                childItem.libraryId = self.libraryId
                childItem.parent = item
                childItem.changedFields.insert(.parent)
                hasMainAttachmentChange = true
            }
        }

        if hasMainAttachmentChange {
            item.updateMainAttachment()
        }
    }

    private func updateTags(with data: ItemDetailState.Data, item: RItem, database: Realm) {
        var tagsDidChange = false

        let tagsToRemove = item.tags.filter(.name(in: data.deletedTags))
        if !tagsToRemove.isEmpty {
            tagsDidChange = true
        }
        database.delete(tagsToRemove)

        for tag in data.tags {
            if let rTag = item.tags.filter(.name(tag.name)).first {
                if tag.color != rTag.color {
                    rTag.color = tag.color
                    rTag.type = .manual
                    tagsDidChange = true
                }
            } else {
                let rTag = RTag()
                rTag.name = tag.name
                rTag.type = .manual
                rTag.color = tag.color
                rTag.libraryId = self.libraryId
                database.add(rTag)

                rTag.item = item
                tagsDidChange = true
            }
        }

        if tagsDidChange {
            item.changedFields.insert(.tags)
        }
    }
}
