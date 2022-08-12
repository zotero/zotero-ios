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
    let version: Int

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        let objects = database.objects(Obj.self).filter(.keys(self.keys, in: self.libraryId))
        for object in objects {
            if object.version != self.version {
                object.version = self.version
            }
            object.resetChanges()
        }
    }
}

struct MarkCollectionAsSyncedAndUpdateDbRequest: DbRequest {
    let libraryId: LibraryIdentifier
    let response: CollectionResponse
    let version: Int

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        guard let collection = database.objects(RCollection.self).filter(.key(self.response.key, in: self.libraryId)).first else { return }

        StoreCollectionsDbRequest.update(collection: collection, data: self.response, libraryId: self.libraryId, database: database)
        collection.resetChanges()
        collection.version = self.version
    }
}

struct MarkItemAsSyncedAndUpdateDbRequest: DbRequest {
    let libraryId: LibraryIdentifier
    let response: ItemResponse
    let version: Int

    unowned let schemaController: SchemaController
    unowned let dateParser: DateParser

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(self.response.key, in: self.libraryId)).first else { return }

        _ = StoreItemDbRequest.update(item: item, libraryId: self.libraryId, with: self.response, schemaController: self.schemaController, dateParser: self.dateParser, database: database)
        item.resetChanges()
        item.version = self.version

        if let parent = item.parent {
            // This is to mitigate the issue in item detail screen (ItemDetailActionHandler.shouldReloadData) where observing of `children` doesn't report changes between `oldValue` and `newValue`.
            parent.version = parent.version
        }
    }
}

struct MarkSearchAsSyncedAndUpdateDbRequest: DbRequest {
    let libraryId: LibraryIdentifier
    let response: SearchResponse
    let version: Int

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        guard let search = database.objects(RSearch.self).filter(.key(self.response.key, in: self.libraryId)).first else { return }

        StoreSearchesDbRequest.update(search: search, data: self.response, libraryId: self.libraryId, database: database)
        search.resetChanges()
        search.version = self.version
    }
}

struct MarkSettingsAsSyncedDbRequest: DbRequest {
    let settings: [(String, LibraryIdentifier)]
    let version: Int

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        for setting in self.settings {
            guard let object = database.objects(RPageIndex.self).filter(.key(setting.0, in: setting.1)).first else { continue }
            if object.version != self.version {
                object.version = self.version
            }
            object.resetChanges()
        }
    }
}
