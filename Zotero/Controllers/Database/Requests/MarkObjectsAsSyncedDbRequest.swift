//
//  MarkObjectsAsSyncedDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 11/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MarkObjectsAsSyncedDbRequest<Obj: UpdatableObject&Syncable>: DbRequest {
    let libraryId: LibraryIdentifier
    let keys: [String]
    let changeUuids: [String: [String]]
    let version: Int

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let objects = database.objects(Obj.self).filter(.keys(self.keys, in: self.libraryId))
        for object in objects {
            if object.version != self.version {
                object.version = self.version
            }

            object.changeType = .syncResponse

            if let uuids = self.changeUuids[object.key] {
                object.deleteChanges(uuids: uuids, database: database)
            }
        }
    }
}

struct MarkSettingsAsSyncedDbRequest: DbRequest {
    let settings: [(String, LibraryIdentifier)]
    let changeUuids: [String]
    let version: Int

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        for setting in self.settings {
            guard let object = database.objects(RPageIndex.self).filter(.key(setting.0, in: setting.1)).first else { continue }
            if object.version != self.version {
                object.version = self.version
            }

            object.changeType = .syncResponse
            
            object.deleteChanges(uuids: self.changeUuids, database: database)
        }
    }
}

struct MarkCollectionAsSyncedAndUpdateDbRequest: DbRequest {
    let libraryId: LibraryIdentifier
    let response: CollectionResponse
    let changeUuids: [String]

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let collection = database.objects(RCollection.self).filter(.key(self.response.key, in: self.libraryId)).first else { return }

        collection.deleteChanges(uuids: self.changeUuids, database: database)
        self.updateUnchangedData(of: collection, with: self.response, database: database)
    }

    private func updateUnchangedData(of collection: RCollection, with response: CollectionResponse, database: Realm) {
        let localChanges = collection.changedFields

        if localChanges.isEmpty {
            StoreCollectionsDbRequest.update(collection: collection, response: self.response, libraryId: self.libraryId, database: database)
            collection.changeType = .syncResponse
            return
        }

        collection.version = response.version
        collection.trash = response.data.isTrash
        collection.changeType = .syncResponse

        if !localChanges.contains(.name) {
            collection.name = response.data.name
        }

        if !localChanges.contains(.parent) {
            StoreCollectionsDbRequest.sync(parentCollection: response.data.parentCollection, libraryId: self.libraryId, collection: collection, database: database)
        }
    }
}

struct MarkItemAsSyncedAndUpdateDbRequest: DbRequest {
    let libraryId: LibraryIdentifier
    let response: ItemResponse
    let changeUuids: [String]

    unowned let schemaController: SchemaController
    unowned let dateParser: DateParser

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(self.response.key, in: self.libraryId)).first else { return }

        item.deleteChanges(uuids: self.changeUuids, database: database)
        self.updateUnchangedData(of: item, with: self.response, database: database)

        if let parent = item.parent {
            // This is to mitigate the issue in item detail screen (ItemDetailActionHandler.shouldReloadData) where observing of `children` doesn't report changes between `oldValue` and `newValue`.
            parent.version = parent.version
        }
    }

    private func updateUnchangedData(of item: RItem, with response: ItemResponse, database: Realm) {
        let localChanges = item.changedFields
        
        if localChanges.isEmpty {
            _ = StoreItemDbRequest.update(item: item, libraryId: self.libraryId, with: response, schemaController: self.schemaController, dateParser: self.dateParser, database: database)
            item.changeType = .syncResponse
            return
        }
        
        item.version = response.version
        item.dateModified = response.dateModified
        item.inPublications = response.inPublications
        item.changeType = .syncResponse
        
        if !localChanges.contains(.trash) {
            item.trash = response.isTrash
        }
        
        if !localChanges.contains(.parent) && item.parent?.key != response.parentKey {
            StoreItemDbRequest.syncParent(key: response.parentKey, libraryId: self.libraryId, item: item, database: database)
        }
        
        // If type changed remotely and we have local field changes, we ignore the type change, so that the type and fields stay in sync (different types can have different fields).
        if !localChanges.contains(.type) && item.rawType != response.rawType && !localChanges.contains(.fields) {
            item.rawType = response.rawType
            item.localizedType = self.schemaController.localized(itemType: response.rawType) ?? response.rawType
        }

        if !localChanges.contains(.fields) {
            _ = StoreItemDbRequest.syncFields(data: response, item: item, database: database, schemaController: self.schemaController, dateParser: self.dateParser)
        }

        if !localChanges.contains(.collections) {
            StoreItemDbRequest.syncCollections(keys: response.collectionKeys, libraryId: self.libraryId, item: item, database: database)
        }
        
        if !localChanges.contains(.tags) {
            StoreItemDbRequest.sync(tags: response.tags, libraryId: self.libraryId, item: item, database: database)
        }

        if !localChanges.contains(.creators) {
            StoreItemDbRequest.sync(creators: response.creators, item: item, schemaController: self.schemaController, database: database)
        }

        if !localChanges.contains(.relations) {
            StoreItemDbRequest.sync(relations: response.relations, item: item, database: database)
        }

        if !localChanges.contains(.rects) {
            StoreItemDbRequest.sync(rects: response.rects ?? [], in: item, database: database)
        }

        if !localChanges.contains(.paths) {
            StoreItemDbRequest.sync(paths: response.paths ?? [], in: item, database: database)
        }

        // Item title depends on item type, creators and fields, so we update derived titles (displayTitle and sortTitle) after everything else synced
        item.updateDerivedTitles()
    }
}

struct MarkSearchAsSyncedAndUpdateDbRequest: DbRequest {
    let libraryId: LibraryIdentifier
    let response: SearchResponse
    let changeUuids: [String]

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let search = database.objects(RSearch.self).filter(.key(self.response.key, in: self.libraryId)).first else { return }

        search.deleteChanges(uuids: self.changeUuids, database: database)
        self.updateUnchangedData(of: search, response: self.response, database: database)
    }

    private func updateUnchangedData(of search: RSearch, response: SearchResponse, database: Realm) {
        let localChanges = search.changedFields

        if localChanges.isEmpty {
            StoreSearchesDbRequest.update(search: search, response: self.response, libraryId: self.libraryId, database: database)
            search.changeType = .syncResponse
            return
        }

        search.trash = response.data.isTrash
        search.version = response.version
        search.changeType = .syncResponse

        if !localChanges.contains(.name) {
            search.name = response.data.name
        }

        if !localChanges.contains(.conditions) {
            StoreSearchesDbRequest.sync(conditions: response.data.conditions, search: search, database: database)
        }
    }
}
