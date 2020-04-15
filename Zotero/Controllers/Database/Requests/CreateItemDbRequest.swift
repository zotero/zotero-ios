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
        database.add(item)

        // Assign library object
        
        switch self.libraryId {
        case .custom(let type):
            let library = database.object(ofType: RCustomLibrary.self, forPrimaryKey: type.rawValue)
            item.customLibrary = library
        case .group(let identifier):
            let group = database.object(ofType: RGroup.self, forPrimaryKey: identifier)
            item.group = group
        }

        var changes: RItemChanges = [.type, .fields]

        if let key = self.collectionKey,
           let collection = database.objects(RCollection.self)
                                    .filter(.key(key, in: self.libraryId))
                                    .first {
            item.collections.append(collection)
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
            
            if field.key == FieldKeys.title || field.baseField == FieldKeys.title {
                item.baseTitle = field.value
            } else if field.key == FieldKeys.date {
                item.setDateFieldMetadata(field.value)
            } else if field.key == FieldKeys.publisher || field.baseField == FieldKeys.publisher {
                item.set(publisher: field.value)
            } else if field.key == FieldKeys.publicationTitle || field.baseField == FieldKeys.publicationTitle {
                item.set(publicationTitle: field.value)
            }
        }

        // Create notes

        for note in self.data.notes {
            let rNote = try CreateNoteDbRequest(note: note,
                                                localizedType: (self.schemaController.localized(itemType: ItemTypes.note) ?? ""),
                                                libraryId: nil).process(in: database)
            rNote.parent = item
            rNote.libraryObject = item.libraryObject
            rNote.changedFields.insert(.parent)
        }

        // Create attachments

        for attachment in self.data.attachments {
            let rAttachment = try CreateAttachmentDbRequest(attachment: attachment,
                                                            localizedType: (self.schemaController.localized(itemType: ItemTypes.attachment) ?? "")).process(in: database)
            rAttachment.libraryObject = item.libraryObject
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

        // Item title depends on item type, creators and fields, so we update derived titles (displayTitle and sortTitle) after everything else synced
        item.updateDerivedTitles()
        // Update changed fields
        item.changedFields = changes
        item.changeType = .user

        return item
    }
}
