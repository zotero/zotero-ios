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
    let data: ItemDetailStore.State.Data
    let schemaController: SchemaController

    var needsWrite: Bool {
        return true
    }

    func process(in database: Realm) throws -> RItem {
        let titleKey = self.schemaController.titleKey(for: self.data.type)
        
        // Create main item
        let item = RItem()
        item.key = KeyGenerator.newKey
        item.rawType = self.data.type
        item.syncState = .synced
        item.dateAdded = Date()
        item.dateModified = Date()
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

        // Create fields

        for field in self.data.allFields(schemaController: self.schemaController) {
            let rField = RItemField()
            rField.key = field.key
            rField.item = item
            rField.value = field.value
            rField.changed = true
            database.add(rField)
            
            if field.key == titleKey {
                item.title = field.value
            }
        }

        // Create notes

        for note in self.data.notes {
            let rNote = try CreateNoteDbRequest(note: note, libraryId: nil).process(in: database)
            rNote.parent = item
            rNote.libraryObject = item.libraryObject
            rNote.changedFields.insert(.parent)
        }

        // Create attachments

        for attachment in self.data.attachments {
            let rAttachment = try CreateAttachmentDbRequest(attachment: attachment, libraryId: nil).process(in: database)
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

        // Create creators

        for (offset, creatorId) in self.data.creatorIds.enumerated() {
            guard let creator = self.data.creators[creatorId] else { continue }

            let rCreator = RCreator()
            rCreator.rawType = creator.type
            rCreator.firstName = creator.firstName
            rCreator.lastName = creator.lastName
            rCreator.name = creator.name
            rCreator.orderId = offset
            rCreator.item = item
            database.add(rCreator)
        }

        if !self.data.creators.isEmpty {
            changes.insert(.creators)
        }

        // Update changed fields
        item.changedFields = changes

        return item
    }
}
