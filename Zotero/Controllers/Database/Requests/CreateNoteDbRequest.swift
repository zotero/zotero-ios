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

    func process(in database: Realm) throws -> RItem {
        let item = RItem()
        item.key = KeyGenerator.newKey
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

        if let key = self.collectionKey,
           let collection = database.objects(RCollection.self).filter(.key(key, in: self.libraryId)).first {
            collection.items.append(item)
            item.changedFields.insert(.collections)
        }

        let noteField = RItemField()
        noteField.key = FieldKeys.Item.note
        noteField.baseKey = nil
        noteField.value = self.note.text
        noteField.changed = true
        noteField.item = item
        database.add(noteField)

        return item
    }
}
