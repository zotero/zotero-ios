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
    let attachments: [ItemDetailStore.StoreState.Attachment]
    let tags: [ItemDetailStore.StoreState.Tag]
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
        var newFields: [RItemField] = []
        var newChildItems: [RItem] = []

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
                                    .filter(Predicates.key(key, in: self.libraryId))
                                    .first {
            item.collections.append(collection)
            changes.insert(.collections)
        }

        self.allFields.forEach { schema in
            let rField = RItemField()
            rField.key = schema.field
            rField.item = item

            if let field = self.fields.first(where: { $0.key == schema.field }) {
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

            newFields.append(rField)
        }

        self.notes.forEach { note in
            let childItem = RItem()
            childItem.key = KeyGenerator.newKey
            childItem.rawType = FieldKeys.note
            childItem.syncState = .synced
            childItem.title = note.title
            childItem.changedFields = [.type, .fields, .parent]
            childItem.libraryObject = item.libraryObject
            childItem.parent = item
            childItem.dateAdded = Date()
            childItem.dateModified = Date()
            newChildItems.append(childItem)

            let noteField = RItemField()
            noteField.key = FieldKeys.note
            noteField.value = note.text
            noteField.changed = true
            noteField.item = childItem
            newFields.append(noteField)
        }

        let attachmentKeys = FieldKeys.attachmentFieldKeys

        self.attachments.forEach { attachment in
            let childItem = RItem()
            childItem.key = attachment.key
            childItem.rawType = FieldKeys.attachment
            childItem.syncState = .synced
            childItem.title = attachment.title
            childItem.changedFields = [.type, .fields, .parent]
            childItem.libraryObject = item.libraryObject
            childItem.parent = item
            childItem.dateAdded = Date()
            childItem.dateModified = Date()
            newChildItems.append(childItem)

            for fieldKey in attachmentKeys {
                let field = RItemField()
                field.key = fieldKey

                switch attachment.type {
                case .file(let file, _):
                    switch fieldKey {
                    case FieldKeys.title, FieldKeys.filename:
                        field.value = attachment.title
                    case FieldKeys.contentType:
                        field.value = file.mimeType
                    case FieldKeys.linkMode:
                        field.value = "imported_file"
                    case FieldKeys.md5:
                        field.value = md5(from: file.createUrl()) ?? ""
                    case FieldKeys.mtime:
                        field.value = "0"
                    default: break
                    }

                case .url(let url):
                    switch fieldKey {
                    case FieldKeys.url:
                        field.value = url.absoluteString
                    case FieldKeys.linkMode:
                        field.value = "linked_url"
                    default: break
                    }
                }

                field.changed = true
                field.item = childItem
                newFields.append(field)
            }
        }

        item.changedFields = changes

        database.add(item)
        database.add(newChildItems)
        database.add(newFields)

        self.tags.forEach { tag in
            if let rTag = database.objects(RTag.self).filter(Predicates.name(tag.name, in: self.libraryId)).first {
                rTag.items.append(item)
            }
        }

        if !self.tags.isEmpty {
            changes.insert(.tags)
        }

        return item
    }
}
