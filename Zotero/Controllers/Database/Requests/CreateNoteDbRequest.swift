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

    let note: ItemDetailStore.State.Note

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> RItem {
        let item = RItem()
        item.key = KeyGenerator.newKey
        item.rawType = ItemTypes.note
        item.syncState = .synced
        item.title = self.note.title
        item.changedFields = [.type, .fields]
        item.dateAdded = Date()
        item.dateModified = Date()
        database.add(item)

        let noteField = RItemField()
        noteField.key = FieldKeys.note
        noteField.value = self.note.text
        noteField.changed = true
        noteField.item = item
        database.add(noteField)

        return item
    }
}
