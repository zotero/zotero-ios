//
//  CreateNoteDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 07/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct CreateNoteDbRequest: DbResponseRequest {
    typealias Response = RItem

    let note: Note
    let localizedType: String
    let libraryId: LibraryIdentifier
    let collectionKey: String?
    let parentKey: String?

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> RItem {
        // Create item
        let item = RItem()
        item.key = self.note.key
        item.rawType = ItemTypes.note
        item.localizedType = self.localizedType
        item.syncState = .synced
        item.set(title: self.note.title)
        item.changedFields = [.type, .fields]
        item.changeType = .user
        item.dateAdded = Date()
        item.dateModified = Date()
        item.libraryId = libraryId
        database.add(item)

        // Assign parent
        if let key = self.parentKey,
           let parent = database.objects(RItem.self).filter(.key(key, in: self.libraryId)).first {
            item.parent = parent
            item.changedFields.insert(.parent)

            // This is to mitigate the issue in item detail screen (ItemDetailActionHandler.shouldReloadData) where observing of `children` doesn't report changes between `oldValue` and `newValue`.
            parent.version = parent.version
        }

        // Assign collection
        if let key = self.collectionKey,
           let collection = database.objects(RCollection.self).filter(.key(key, in: self.libraryId)).first {
            collection.items.append(item)
            item.changedFields.insert(.collections)
        }

        // Create fields
        let noteField = RItemField()
        noteField.key = FieldKeys.Item.note
        noteField.baseKey = nil
        noteField.value = self.note.text
        noteField.changed = true
        item.fields.append(noteField)

        // Create tags
        let allTags = database.objects(RTag.self).filter(.library(with: self.libraryId))
        for tag in self.note.tags {
            let rTag: RTag

            if let existing = allTags.filter(.name(tag.name)).first {
                rTag = existing
            } else {
                rTag = RTag()
                rTag.name = tag.name
                rTag.color = tag.color
                rTag.libraryId = self.libraryId
                database.add(rTag)
            }

            let rTypedTag = RTypedTag()
            rTypedTag.type = .manual
            database.add(rTypedTag)

            rTypedTag.item = item
            rTypedTag.tag = rTag
        }

        return item
    }
}
