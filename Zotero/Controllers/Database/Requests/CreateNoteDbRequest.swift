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
        noteField.item = item
        database.add(noteField)

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
