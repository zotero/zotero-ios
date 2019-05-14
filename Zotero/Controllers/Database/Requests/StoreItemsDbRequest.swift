//
//  StoreItemsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack
import RealmSwift

enum StoreItemsError: Error {
    case itemDeleted(ItemResponse)
}

struct StoreItemsDbRequest: DbResponseRequest {
    typealias Response = [StoreItemsError]

    let response: [ItemResponse]
    let trash: Bool
    let schemaController: SchemaController

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> [StoreItemsError] {
        var errors: [StoreItemsError] = []
        for data in self.response {
            do {
                try self.store(data: data, to: database, schemaController: self.schemaController)
            } catch let error as StoreItemsError {
                errors.append(error)
            } catch let error {
                throw error
            }
        }
        return errors
    }

    private func store(data: ItemResponse, to database: Realm, schemaController: SchemaController) throws {
        guard let libraryId = data.library.libraryId else { throw DbError.primaryKeyUnavailable }

        let item: RItem
        let predicate = Predicates.keyInLibrary(key: data.key, libraryId: libraryId)
        if let existing = database.objects(RItem.self).filter(predicate).first {
            item = existing
        } else {
            item = RItem()
            database.add(item)
        }

        if item.deleted {
            throw StoreItemsError.itemDeleted(data)
        }

        item.key = data.key
        item.type = data.type
        item.creatorSummary = data.creatorSummary ?? ""
        item.parsedDate = data.parsedDate ?? ""
        item.version = data.version
        item.trash = data.isTrash
        item.dateModified = data.dateModified
        item.dateAdded = data.dateAdded
        item.syncState = .synced

        self.syncFields(data: data, item: item, database: database, schemaController: schemaController)
        try self.syncLibrary(identifier: libraryId, libraryName: data.library.name, item: item, database: database)
        self.syncParent(key: data.parentKey, libraryId: libraryId, item: item, database: database)
        self.syncCollections(keys: data.collectionKeys, libraryId: libraryId, item: item, database: database)
        try self.syncTags(data.tags, libraryId: libraryId, item: item, database: database)
        self.syncCreators(data: data, item: item, database: database)
        self.syncRelations(data: data, item: item, database: database)
    }

    private func syncFields(data: ItemResponse, item: RItem, database: Realm, schemaController: SchemaController) {
        let titleField = schemaController.titleField(for: item.rawType)
        let allFieldKeys = Array(data.fields.keys)
        let toRemove = item.fields.filter("NOT key IN %@", allFieldKeys)
        database.delete(toRemove)
        allFieldKeys.forEach { key in
            let value = data.fields[key] ?? ""
            if let existing = item.fields.filter("key = %@", key).first {
                existing.value = value
            } else {
                let field = RItemField()
                field.key = key
                field.value = value
                field.item = item
                database.add(field)
            }
            if key == titleField || (item.type == .note && key == FieldKeys.note) {
                var title = value
                if key == FieldKeys.note {
                    title = title.strippedHtml ?? title
                }
                item.title = title
            }
        }
    }

    private func syncLibrary(identifier: LibraryIdentifier, libraryName: String, item: RItem, database: Realm) throws {
        let libraryData = try database.autocreatedLibraryObject(forPrimaryKey: identifier)
        if libraryData.0 {
            switch libraryData.1 {
            case .group(let object):
                object.name = libraryName
                object.syncState = .outdated
            case .custom: break
            }
        }
        item.libraryObject = libraryData.1
    }

    private func syncParent(key: String?, libraryId: LibraryIdentifier, item: RItem, database: Realm) {
        item.parent = nil

        guard let key = key else { return }

        let parent: RItem
        let predicate = Predicates.keyInLibrary(key: key, libraryId: libraryId)

        if let existing = database.objects(RItem.self).filter(predicate).first {
            parent = existing
        } else {
            parent = RItem()
            parent.key = key
            parent.syncState = .dirty
            parent.libraryObject = item.libraryObject
            database.add(parent)
        }

        item.parent = parent
    }

    private func syncCollections(keys: Set<String>, libraryId: LibraryIdentifier, item: RItem, database: Realm) {
        item.collections.removeAll()

        guard !keys.isEmpty else { return }

        var remainingCollections = keys
        let predicate = Predicates.keysInLibrary(keys: keys, libraryId: libraryId)
        let existingCollections = database.objects(RCollection.self).filter(predicate)

        for collection in existingCollections {
            item.collections.append(collection)
            remainingCollections.remove(collection.key)
        }

        for key in remainingCollections {
            let collection = RCollection()
            collection.key = key
            collection.syncState = .dirty
            collection.libraryObject = item.libraryObject
            database.add(collection)
            item.collections.append(collection)
        }
    }

    private func syncTags(_ tags: [TagResponse], libraryId: LibraryIdentifier, item: RItem, database: Realm) throws {
        var existingIndices: Set<Int> = []
        item.tags.forEach { tag in
            if let index = tags.firstIndex(where: { $0.tag == tag.name }) {
                existingIndices.insert(index)
            } else {
                if let index = tag.items.index(of: item) {
                    tag.items.remove(at: index)
                }
            }
        }

        for object in tags.enumerated() {
            guard !existingIndices.contains(object.offset) else { continue }
            let tag: RTag
            let predicate = Predicates.nameInLibrary(name: object.element.tag, libraryId: libraryId)
            if let existing = database.objects(RTag.self).filter(predicate).first {
                tag = existing
            } else {
                tag = RTag()
                tag.name = object.element.tag
                tag.libraryObject = item.libraryObject
                database.add(tag)
            }
            tag.items.append(item)
        }
    }

    private func syncCreators(data: ItemResponse, item: RItem, database: Realm) {
        database.delete(item.creators)

        for object in data.creators.enumerated() {
            let firstName = object.element.firstName ?? ""
            let lastName = object.element.lastName ?? ""
            let name = object.element.name ?? ""

            let creator = RCreator()
            creator.rawType = object.element.creatorType
            creator.firstName = firstName
            creator.lastName = lastName
            creator.name = name
            database.add(creator)
            creator.orderId = object.offset
            creator.item = item
        }
    }

    private func syncRelations(data: ItemResponse, item: RItem, database: Realm) {
        let allKeys = Array(data.relations.keys)
        let toRemove = item.relations.filter("NOT type IN %@", allKeys)
        database.delete(toRemove)

        allKeys.forEach { key in
            let relation: RRelation
            if let existing = item.relations.filter("type = %@", key).first {
                relation = existing
            } else {
                relation = RRelation()
                relation.type = key
                relation.item = item
                database.add(relation)
            }
            relation.urlString = data.relations[key] ?? ""
        }
    }
}
