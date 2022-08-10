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

    let key: String
    let libraryId: LibraryIdentifier
    let collectionKey: String?
    let data: ItemDetailState.Data
    let attachments: [Attachment]
    let notes: [Note]
    let tags: [Tag]
    let schemaController: SchemaController
    let dateParser: DateParser

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> RItem {
        // Create main item
        let item = RItem()
        item.key = self.key
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
            item.creators.append(rCreator)
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
            rField.value = field.value
            rField.changed = true
            item.fields.append(rField)
            
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

        for note in self.notes {
            let rNote = try CreateNoteDbRequest(note: note,
                                                localizedType: (self.schemaController.localized(itemType: ItemTypes.note) ?? ""),
                                                libraryId: self.libraryId,
                                                collectionKey: nil,
                                                parentKey: nil).process(in: database)
            rNote.parent = item
            rNote.changedFields.insert(.parent)
        }

        // Create attachments

        for attachment in self.attachments {
            // Existing standalone attachment can be assigend as a child for new item, check whether attachment exists and update/create accordingly.
            if let rAttachment = database.objects(RItem.self).filter(.key(attachment.key, in: self.libraryId)).first {
                // In this case the attachment doesn't change anyhow, just assign this new item as a parent.
                rAttachment.parent = item
                rAttachment.changedFields.insert(.parent)
                rAttachment.changeType = .user
            } else {
                let rAttachment = try CreateAttachmentDbRequest(attachment: attachment,
                                                                localizedType: (self.schemaController.localized(itemType: ItemTypes.attachment) ?? ""),
                                                                collections: [], tags: []).process(in: database)
                rAttachment.libraryId = self.libraryId
                rAttachment.parent = item
                rAttachment.changedFields.insert(.parent)
            }
        }

        // Create tags

        let allTags = database.objects(RTag.self)
        for tag in self.tags {
            guard let rTag = allTags.filter(.name(tag.name, in: self.libraryId)).first else { continue }

            let rTypedTag = RTypedTag()
            rTypedTag.type = .manual
            database.add(rTypedTag)

            rTypedTag.item = item
            rTypedTag.tag = rTag
        }
        if !self.tags.isEmpty {
            changes.insert(.tags)
        }

        // Item title depends on item type, creators and fields, so derived titles (displayTitle and sortTitle) are updated after everything else synced
        item.updateDerivedTitles()
        // Update changed fields
        item.changedFields = changes
        item.changeType = .user

        return item
    }
}
