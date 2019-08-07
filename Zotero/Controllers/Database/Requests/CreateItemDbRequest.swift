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
    let type: String
    let fields: [ItemDetailStore.StoreState.Field]
    let notes: [ItemDetailStore.StoreState.Note]
    let attachments: [ItemDetailStore.StoreState.Attachment]
    let tags: [ItemDetailStore.StoreState.Tag]

    var needsWrite: Bool {
        return true
    }

    func process(in database: Realm) throws -> RItem {
        // Create main item
        let item = RItem()
        item.key = KeyGenerator.newKey
        item.rawType = self.type
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
                                    .filter(Predicates.key(key, in: self.libraryId))
                                    .first {
            item.collections.append(collection)
            changes.insert(.collections)
        }

        // Create fields

        for field in self.fields {
            let rField = RItemField()
            rField.key = field.key
            rField.item = item
            rField.value = field.value
            rField.changed = field.changed
            database.add(rField)
        }

        // Create notes

        for note in self.notes {
            let rNote = try CreateNoteDbRequest(note: note).process(in: database)
            rNote.parent = item
            rNote.libraryObject = item.libraryObject
            rNote.changedFields.insert(.parent)
        }

        // Create attachments

        for attachment in self.attachments {
            let rAttachment = try CreateAttachmentDbRequest(attachment: attachment).process(in: database)
            rAttachment.libraryObject = item.libraryObject
            rAttachment.parent = item
            rAttachment.changedFields.insert(.parent)
        }

        // Create tags

        self.tags.forEach { tag in
            if let rTag = database.objects(RTag.self).filter(Predicates.name(tag.name, in: self.libraryId)).first {
                rTag.items.append(item)
            }
        }
        if !self.tags.isEmpty {
            changes.insert(.tags)
        }

        // Update changed fields
        item.changedFields = changes

        return item
    }
}
