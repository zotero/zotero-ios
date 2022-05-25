//
//  StoreItemsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct StoreItemsResponse {
    struct FilenameChange {
        let key: String
        let oldName: String
        let newName: String
        let contentType: String
    }

    enum Error: Swift.Error {
        case itemDeleted(ItemResponse)
        case itemChanged(ItemResponse)
    }

    let changedFilenames: [FilenameChange]
    let conflicts: [Error]
}

struct StoreItemsDbResponseRequest: DbResponseRequest {
    typealias Response = StoreItemsResponse

    let responses: [ItemResponse]
    unowned let schemaController: SchemaController
    unowned let dateParser: DateParser
    let preferResponseData: Bool

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> StoreItemsResponse {
        var filenameChanges: [StoreItemsResponse.FilenameChange] = []
        var errors: [StoreItemsResponse.Error] = []

        for response in self.responses {
            do {
                let (_, change) = try StoreItemDbRequest(response: response, schemaController: self.schemaController, dateParser: self.dateParser, preferRemoteData: self.preferResponseData).process(in: database)
                if let change = change {
                    filenameChanges.append(change)
                }
            } catch let error as StoreItemsResponse.Error {
                errors.append(error)
            } catch let error {
                throw error
            }
        }

        return StoreItemsResponse(changedFilenames: filenameChanges, conflicts: errors)
    }
}

struct StoreItemDbRequest: DbResponseRequest {
    typealias Response = (RItem, StoreItemsResponse.FilenameChange?)

    let response: ItemResponse
    unowned let schemaController: SchemaController
    unowned let dateParser: DateParser
    let preferRemoteData: Bool

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> (RItem, StoreItemsResponse.FilenameChange?) {
        guard let libraryId = self.response.library.libraryId else { throw DbError.primaryKeyUnavailable }

        let item: RItem
        if let existing = database.objects(RItem.self).filter(.key(self.response.key, in: libraryId)).first {
            item = existing
        } else {
            item = RItem()
            database.add(item)
        }

        if !self.preferRemoteData {
            if item.deleted {
                throw StoreItemsResponse.Error.itemDeleted(self.response)
            }

            if item.isChanged {
                throw StoreItemsResponse.Error.itemChanged(self.response)
            }
        }

        if self.preferRemoteData {
            item.deleted = false
            item.resetChanges()
        }

        return StoreItemDbRequest.update(item: item, libraryId: libraryId, with: self.response, schemaController: self.schemaController, dateParser: self.dateParser, database: database)
    }

    static func update(item: RItem, libraryId: LibraryIdentifier, with response: ItemResponse, schemaController: SchemaController, dateParser: DateParser, database: Realm) -> (RItem, StoreItemsResponse.FilenameChange?) {
        item.key = response.key
        item.rawType = response.rawType
        item.localizedType = schemaController.localized(itemType: response.rawType) ?? ""
        item.inPublications = response.inPublications
        item.version = response.version
        item.trash = response.isTrash
        item.dateModified = response.dateModified
        item.dateAdded = response.dateAdded
        item.syncState = .synced
        item.syncRetries = 0
        item.lastSyncDate = Date(timeIntervalSince1970: 0)
        item.changeType = .sync
        item.libraryId = libraryId

        let filenameChange = self.syncFields(data: response, item: item, database: database, schemaController: schemaController, dateParser: dateParser)
        self.syncParent(key: response.parentKey, libraryId: libraryId, item: item, database: database)
        self.syncCollections(keys: response.collectionKeys, libraryId: libraryId, item: item, database: database)
        self.syncTags(response.tags, libraryId: libraryId, item: item, database: database)
        self.syncCreators(data: response, item: item, schemaController: schemaController, database: database)
        self.syncRelations(data: response, item: item, database: database)
        self.syncLinks(data: response, item: item, database: database)
        self.syncUsers(createdBy: response.createdBy, lastModifiedBy: response.lastModifiedBy, item: item, database: database)
        self.sync(rects: response.rects ?? [], in: item, database: database)
        self.sync(paths: response.paths ?? [], in: item, database: database)

        // Item title depends on item type, creators and fields, so we update derived titles (displayTitle and sortTitle) after everything else synced
        item.updateDerivedTitles()

        return (item, filenameChange)
    }

    private static func syncFields(data: ItemResponse, item: RItem, database: Realm, schemaController: SchemaController, dateParser: DateParser) -> StoreItemsResponse.FilenameChange? {
        var oldName: String?
        var newName: String?
        var contentType: String?
        let allFieldKeys = Array(data.fields.keys)

        let toRemove = item.fields.filter("NOT key IN %@", allFieldKeys)
        database.delete(toRemove)

        var date: String?
        var publisher: String?
        var publicationTitle: String?
        var sortIndex: String?
        var md5: String?

        for key in allFieldKeys {
            let value = data.fields[key] ?? ""
            var field: RItemField

            if let existing = item.fields.filter(.key(key)).first {
                if (existing.key == FieldKeys.Item.Attachment.filename || existing.baseKey == FieldKeys.Item.Attachment.filename) && existing.value != value {
                    oldName = existing.value
                    newName = value
                }
                // Backend returns "<null>" for md5 and mtime for item which was submitted, but attachment has not yet been uploaded. Just ignore these values, we have correct values stored locally
                // and they'll be submitted on upload of attachment.
                if value != "<null>" || existing.value.isEmpty {
                    existing.value = value
                }
                field = existing
            } else {
                field = RItemField()
                field.key = key
                field.baseKey = schemaController.baseKey(for: data.rawType, field: key)
                field.value = value
                item.fields.append(field)
            }

            switch (field.key, field.baseKey) {
            case (FieldKeys.Item.title, _), (_, FieldKeys.Item.title):
                item.baseTitle = value
            case (FieldKeys.Item.note, _) where item.rawType == ItemTypes.note:
                item.baseTitle = value.notePreview ?? value
            case (FieldKeys.Item.date, _):
                date = value
            case (FieldKeys.Item.publisher, _), (_, FieldKeys.Item.publisher):
                publisher = value
            case (FieldKeys.Item.publicationTitle, _), (_, FieldKeys.Item.publicationTitle):
                publicationTitle = value
            case (FieldKeys.Item.Annotation.sortIndex, _):
                sortIndex = value
            case (FieldKeys.Item.Attachment.md5, _):
                if value != "<null>" {
                    md5 = value
                }
            case (FieldKeys.Item.Attachment.contentType, _), (_, FieldKeys.Item.Attachment.contentType):
                contentType = value
            default: break
            }
        }

        item.setDateFieldMetadata(date, parser: dateParser)
        item.set(publisher: publisher)
        item.set(publicationTitle: publicationTitle)
        item.annotationSortIndex = sortIndex ?? ""
        item.backendMd5 = md5 ?? ""

        if let oldName = oldName, let newName = newName, let contentType = contentType {
            return StoreItemsResponse.FilenameChange(key: item.key, oldName: oldName, newName: newName, contentType: contentType)
        }
        return nil
    }

    private static func sync(rects: [[Double]], in item: RItem, database: Realm) {
        guard self.rects(rects, differFrom: item.rects) else { return }

        database.delete(item.rects)
        for rect in rects {
            let rRect = RRect()
            rRect.minX = rect[0]
            rRect.minY = rect[1]
            rRect.maxX = rect[2]
            rRect.maxY = rect[3]
            item.rects.append(rRect)
        }
    }

    private static func rects(_ rects: [[Double]], differFrom itemRects: List<RRect>) -> Bool {
        if rects.count != itemRects.count {
            return true
        }

        for rect in rects {
            // If rect can't be found in item, it must have changed
            if itemRects.filter("minX == %d and minY == %d and maxX == %d and maxY == %d", rect[0], rect[1], rect[2], rect[3]).first == nil {
                return true
            }
        }

        return false
    }

    private static func sync(paths: [[Double]], in item: RItem, database: Realm) {
        guard self.paths(paths, differFrom: item.paths) else { return }

        for path in item.paths {
            database.delete(path.coordinates)
        }
        database.delete(item.paths)

        for (idx, path) in paths.enumerated() {
            let rPath = RPath()
            rPath.sortIndex = idx

            for (idy, value) in path.enumerated() {
                let rCoordinate = RPathCoordinate()
                rCoordinate.value = value
                rCoordinate.sortIndex = idy
                rPath.coordinates.append(rCoordinate)
            }

            item.paths.append(rPath)
        }
    }

    private static func paths(_ paths: [[Double]], differFrom itemPaths: List<RPath>) -> Bool {
        if paths.count != itemPaths.count {
            return true
        }

        let sortedPaths = itemPaths.sorted(byKeyPath: "sortIndex")

        for idx in 0..<paths.count {
            let path = paths[idx]
            let itemPath = sortedPaths[idx]

            if path.count != itemPath.coordinates.count {
                return true
            }

            let sortedCoordinates = itemPath.coordinates.sorted(byKeyPath: "sortIndex")

            for idy in 0..<path.count {
                if path[idy] != sortedCoordinates[idy].value {
                    return true
                }
            }
        }

        return false
    }

    private static func syncParent(key: String?, libraryId: LibraryIdentifier, item: RItem, database: Realm) {
        guard let key = key else {
            if item.parent != nil {
                item.parent = nil
            }
            return
        }

        let parent: RItem

        if let existing = database.objects(RItem.self).filter(.key(key, in: libraryId)).first {
            parent = existing
        } else {
            parent = RItem()
            parent.key = key
            parent.syncState = .dirty
            parent.libraryId = libraryId
            database.add(parent)
        }

        item.parent = parent
    }

    private static func syncCollections(keys: Set<String>, libraryId: LibraryIdentifier, item: RItem, database: Realm) {
        // Remove item from collections, which are not in the `keys` array anymore
        for collection in item.collections.filter(.key(notIn: keys)) {
            guard let index = collection.items.index(of: item) else { continue }
            collection.items.remove(at: index)
        }

        guard !keys.isEmpty else { return }

        var toCreateKeys = keys
        let existingCollections = database.objects(RCollection.self).filter(.keys(keys, in: libraryId))

        // Add item to existing collections, which don't already contain the item
        for collection in existingCollections {
            if collection.items.filter(.key(item.key)).first == nil {
                collection.items.append(item)
            }
            toCreateKeys.remove(collection.key)
        }

        // Create remaining unknown collections
        for key in toCreateKeys {
            let collection = RCollection()
            collection.key = key
            collection.syncState = .dirty
            collection.libraryId = libraryId
            database.add(collection)

            collection.items.append(item)
        }
    }

    private static func syncTags(_ tags: [TagResponse], libraryId: LibraryIdentifier, item: RItem, database: Realm) {
        // Remove item from tags, which are not in the `tags` array anymore
        let toRemove = item.tags.filter(.tagName(notIn: tags.map({ $0.tag })))
        let baseTagsToRemove = (try? ReadBaseTagsToDeleteDbRequest(fromTags: toRemove).process(in: database)) ?? []

        database.delete(toRemove)
        if !baseTagsToRemove.isEmpty {
            database.delete(database.objects(RTag.self).filter(.name(in: baseTagsToRemove)))
        }

        guard !tags.isEmpty else { return }

        let allTags = database.objects(RTag.self)

        for tag in tags {
            if let existing = item.tags.filter(.tagName(tag.tag)).first {
                if existing.type != tag.type {
                    existing.type = tag.type
                }
                continue
            }

            let rTag: RTag

            if let existing = allTags.filter(.name(tag.tag, in: libraryId)).first {
                rTag = existing
            } else {
                rTag = RTag()
                rTag.name = tag.tag
                rTag.libraryId = libraryId
                database.add(rTag)
            }

            let rTypedTag = RTypedTag()
            rTypedTag.type = tag.type
            database.add(rTypedTag)

            rTypedTag.item = item
            rTypedTag.tag = rTag
        }
    }

    private static func syncCreators(data: ItemResponse, item: RItem, schemaController: SchemaController, database: Realm) {
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
            creator.orderId = object.offset
            creator.primary = schemaController.creatorIsPrimary(creator.rawType, itemType: item.rawType)
            item.creators.append(creator)
        }

        item.updateCreatorSummary()
    }

    private static func syncRelations(data: ItemResponse, item: RItem, database: Realm) {
        let allKeys = Array(data.relations.keys)
        let toRemove = item.relations.filter("NOT type IN %@", allKeys)
        database.delete(toRemove)

        for key in allKeys {
            guard let anyValue = data.relations[key] else { continue }

            let value: String
            if let _value = anyValue as? String {
                value = _value
            } else if let _value = anyValue as? [String] {
                value = _value.joined(separator: ";")
            } else {
                value = ""
            }

            let relation: RRelation
            if let existing = item.relations.filter("type = %@", key).first {
                relation = existing
            } else {
                relation = RRelation()
                relation.type = key
                item.relations.append(relation)
            }

            relation.urlString = value
        }
    }

    private static func syncLinks(data: ItemResponse, item: RItem, database: Realm) {
        database.delete(item.links)

        guard let links = data.links else { return }

        if let link = links.`self` {
            self.syncLink(data: link, type: LinkType.me.rawValue, item: item, database: database)
        }
        if let link = links.up {
            self.syncLink(data: link, type: LinkType.up.rawValue, item: item, database: database)
        }
        if let link = links.alternate {
            self.syncLink(data: link, type: LinkType.alternate.rawValue, item: item, database: database)
        }
        if let link = links.enclosure {
            self.syncLink(data: link, type: LinkType.enclosure.rawValue, item: item, database: database)
        }
    }

    private static func syncLink(data: LinkResponse, type: String, item: RItem, database: Realm) {
        let link = RLink()
        link.type = type
        link.contentType = data.type ?? ""
        link.href = data.href
        link.title = data.title ?? ""
        link.length = data.length ?? 0
        item.links.append(link)
    }

    private static func syncUsers(createdBy: UserResponse?, lastModifiedBy: UserResponse?, item: RItem, database: Realm) {
        if item.createdBy?.isInvalidated == true || item.createdBy?.identifier != createdBy?.id {
            let user = item.createdBy?.isInvalidated == true ? nil : item.createdBy

            item.createdBy = createdBy.flatMap({ self.createUser(from: $0, in: database) })

            if let user = user, user.createdBy.isEmpty && user.modifiedBy.isEmpty {
                database.delete(user)
            }
        }

        if item.lastModifiedBy?.isInvalidated == true || item.lastModifiedBy?.identifier != lastModifiedBy?.id {
            let user = item.lastModifiedBy?.isInvalidated == true ? nil : item.lastModifiedBy

            item.lastModifiedBy = lastModifiedBy.flatMap({ self.createUser(from: $0, in: database) })

            if let user = user, user.createdBy.isEmpty && user.modifiedBy.isEmpty {
                database.delete(user)
            }
        }
    }

    private static func createUser(from response: UserResponse, in database: Realm) -> RUser {
        if let user = database.object(ofType: RUser.self, forPrimaryKey: response.id) {
            if user.name != response.name {
                user.name = response.name
            }
            if user.username != response.username {
                user.username = response.username
            }
            return user
        }

        let user = RUser()
        user.identifier = response.id
        user.name = response.name
        user.username = response.username
        database.add(user)
        return user
    }
}
