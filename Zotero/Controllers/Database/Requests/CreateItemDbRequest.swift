//
//  CreateItemDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 26/04/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct CreateItemDbRequest: DbResponseRequest {
    typealias Response = RItem

    let libraryId: LibraryIdentifier
    let collectionKey: String?
    let data: ItemDetailState.Data
    let schemaController: SchemaController
    let dateParser: DateParser

    var needsWrite: Bool {
        return true
    }

    func process(in database: Realm) throws -> RItem {
        // Create main item
        let item = RItem()
        item.key = KeyGenerator.newKey
        item.rawType = self.data.type
        item.localizedType = self.schemaController.localized(itemType: self.data.type) ?? ""
        item.syncState = .synced
        item.dateAdded = self.data.dateAdded
        item.dateModified = self.data.dateModified
        item.libraryId = self.libraryId
        database.add(item)

        var changes: RItemChanges = [.type, .fields]

        if let key = self.collectionKey,
           let collection = database.objects(RCollection.self).filter(.key(key, in: self.libraryId)).first {
            collection.items.append(item)
            changes.insert(.collections)
        }

        // Create creators

        for (offset, creatorId) in self.data.creatorIds.enumerated() {
            guard let creator = self.data.creators[creatorId] else { continue }

            let rCreator = RCreator()
            rCreator.rawType = creator.type
            rCreator.firstName = creator.firstName
            rCreator.lastName = creator.lastName
            rCreator.name = creator.name
            rCreator.orderId = offset
            rCreator.primary = creator.primary
            rCreator.item = item
            database.add(rCreator)
        }
        item.updateCreatorSummary()

        if !self.data.creators.isEmpty {
            changes.insert(.creators)
        }

        // Create fields

        for field in self.data.databaseFields(schemaController: self.schemaController) {
            let rField = RItemField()
            rField.key = field.key
            rField.baseKey = field.baseField
            rField.item = item
            rField.value = field.value
            rField.changed = true
            database.add(rField)
            
            if field.key == FieldKeys.Item.title || field.baseField == FieldKeys.Item.title {
                item.baseTitle = field.value
            } else if field.key == FieldKeys.Item.date {
                item.setDateFieldMetadata(field.value, parser: self.dateParser)
            } else if field.key == FieldKeys.Item.publisher || field.baseField == FieldKeys.Item.publisher {
                item.set(publisher: field.value)
            } else if field.key == FieldKeys.Item.publicationTitle || field.baseField == FieldKeys.Item.publicationTitle {
                item.set(publicationTitle: field.value)
            }
        }

        // Create notes

        for note in self.data.notes {
            let rNote = try CreateNoteDbRequest(note: note,
                                                localizedType: (self.schemaController.localized(itemType: ItemTypes.note) ?? ""),
                                                libraryId: self.libraryId,
                                                collectionKey: nil).process(in: database)
            rNote.parent = item
            rNote.changedFields.insert(.parent)
        }

        // Create attachments

        for attachment in self.data.attachments {
            let rAttachment = try CreateAttachmentDbRequest(attachment: attachment,
                                                            localizedType: (self.schemaController.localized(itemType: ItemTypes.attachment) ?? ""),
                                                            collections: []).process(in: database)
            rAttachment.libraryId = self.libraryId
            rAttachment.parent = item
            rAttachment.changedFields.insert(.parent)
        }

        // Create tags

        self.data.tags.forEach { tag in
            if let rTag = database.objects(RTag.self).filter(.name(tag.name, in: self.libraryId)).first {
                rTag.items.append(item)
            }
        }
        if !self.data.tags.isEmpty {
            changes.insert(.tags)
        }

        // Item title depends on item type, creators and fields, so derived titles (displayTitle and sortTitle) are updated after everything else synced
        item.updateDerivedTitles()
        // Main attachment depends on attachments, so it's updated after everything else
        item.updateMainAttachment()
        // Update changed fields
        item.changedFields = changes
        item.changeType = .user

        return item
    }
}
