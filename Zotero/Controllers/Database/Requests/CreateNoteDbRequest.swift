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
    let localizedType: String
    let libraryId: LibraryIdentifier?

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> RItem {
        let item = RItem()
        item.key = KeyGenerator.newKey
        item.rawType = ItemTypes.note
        item.localizedType = self.localizedType
        item.syncState = .synced
        item.setTitle(self.note.title)
        item.changedFields = [.type, .fields]
        item.dateAdded = Date()
        item.dateModified = Date()

        if let libraryId = self.libraryId {
            switch libraryId {
            case .custom(let type):
                let library = database.object(ofType: RCustomLibrary.self, forPrimaryKey: type.rawValue)
                item.customLibrary = library
            case .group(let identifier):
                let group = database.object(ofType: RGroup.self, forPrimaryKey: identifier)
                item.group = group
            }
        }

        database.add(item)

        let noteField = RItemField()
        noteField.key = FieldKeys.note
        noteField.baseKey = nil
        noteField.value = self.note.text
        noteField.changed = true
        noteField.item = item
        database.add(noteField)

        return item
    }
}
