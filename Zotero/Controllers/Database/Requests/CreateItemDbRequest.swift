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
    let title: String
    let abstract: String?
    let fields: [ItemDetailStore.StoreState.Field]
    let notes: [ItemDetailStore.StoreState.Note]
    let allFields: [FieldSchema]

    var needsWrite: Bool {
        return true
    }

    func process(in database: Realm) throws -> RItem {
        let item = RItem()
        item.key = KeyGenerator.newKey
        item.rawType = self.type
        item.title = self.title
        item.syncState = .synced
        item.dateAdded = Date()
        item.dateModified = Date()

        var changes: RItemChanges = [.type, .fields]

        switch self.libraryId {
        case .custom(let type):
            let library = database.object(ofType: RCustomLibrary.self, forPrimaryKey: type.rawValue)
            item.customLibrary = library
        case .group(let identifier):
            let group = database.object(ofType: RGroup.self, forPrimaryKey: identifier)
            item.group = group
        }

        if let key = self.collectionKey,
           let collection = database.objects(RCollection.self)
                                    .filter(Predicates.keyInLibrary(key: key, libraryId: self.libraryId))
                                    .first {
            item.collections.append(collection)
            changes.insert(.collections)
        }

        var fields: [RItemField] = []
        self.allFields.forEach { schema in
            let rField = RItemField()
            rField.key = schema.field
            rField.item = item

            if let field = self.fields.first(where: { $0.type == schema.field }) {
                rField.value = field.value
                rField.changed = field.changed
            } else {
                if schema.field == FieldKeys.abstract {
                    if let abstract = self.abstract {
                        rField.value = abstract
                        rField.changed = true
                    }
                } else if schema.field == FieldKeys.title ||
                          schema.baseField == FieldKeys.title {
                    rField.value = self.title
                    rField.changed = true
                }
            }

            fields.append(rField)
        }

        var notes: [RItem] = []
        var noteFields: [RItemField] = []
        self.notes.forEach { note in
            let childItem = RItem()
            childItem.key = KeyGenerator.newKey
            childItem.type = .note
            childItem.syncState = .synced
            childItem.title = note.title
            childItem.changedFields = [.type, .fields, .parent]
            childItem.libraryObject = item.libraryObject
            childItem.parent = item
            childItem.dateAdded = Date()
            childItem.dateModified = Date()
            notes.append(childItem)

            let noteField = RItemField()
            noteField.key = FieldKeys.note
            noteField.value = note.text
            noteField.changed = true
            noteField.item = childItem
            noteFields.append(noteField)
        }

        item.changedFields = changes

        database.add(item)
        database.add(fields)
        database.add(notes)
        database.add(noteFields)

        return item
    }
}
