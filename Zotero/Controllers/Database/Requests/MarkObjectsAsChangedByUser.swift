//
//  MarkObjectsAsChangedByUser.swift
//  Zotero
//
//  Created by Michal Rentka on 11.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct MarkObjectsAsChangedByUser: DbRequest {
    let libraryId: LibraryIdentifier
    let collections: [String]
    let items: [String]

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        self.markCollections(with: self.collections, database: database)
        self.markItems(with: self.items, database: database)
    }

    private func markItems(with keys: [String], database: Realm) {
        let objects = database.objects(RItem.self).filter(.keys(keys, in: self.libraryId))
        for object in objects {
            guard !object.isInvalidated else { continue } // If object is invalidated it has already been removed by some parent before
            object.markAsChanged(in: database)
        }
    }

    private func markCollections(with keys: [String], database: Realm) {
        let objects = database.objects(RCollection.self).filter(.keys(keys, in: self.libraryId))
        for object in objects {
            guard !object.isInvalidated else { continue }
            object.markAsChanged(in: database)
        }
    }
}

/// Marks local synced objects as changed if they are not found remotely (sync versions request doesn't return them in the version dictionary).
struct MarkOtherObjectsAsChangedByUser: DbRequest {
    let syncObject: SyncObject
    let versions: [String: Int]
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        switch self.syncObject {
        case .collection:
            let objects = database.objects(RCollection.self).filter(.library(with: self.libraryId))
            self.markAsChanged(notIn: self.versions, objects: objects, database: database)
        case .search:
            let objects = database.objects(RSearch.self).filter(.library(with: self.libraryId))
            self.markAsChanged(notIn: self.versions, objects: objects, database: database)
        case .item:
            let objects = database.objects(RItem.self).filter(.library(with: self.libraryId)).filter(.isTrash(false))
            self.markAsChanged(notIn: self.versions, objects: objects, database: database)
        case .trash:
            let objects = database.objects(RItem.self).filter(.library(with: self.libraryId)).filter(.isTrash(true))
            self.markAsChanged(notIn: self.versions, objects: objects, database: database)
        case .settings: break
        }
    }

    private func markAsChanged<Obj: UpdatableObject&Syncable&Deletable>(notIn: [String: Int], objects: Results<Obj>, database: Realm) {
        for object in objects {
            guard !object.isInvalidated && object.syncState == .synced && !self.versions.keys.contains(object.key) else { continue }
            if object.deleted {
                DDLogWarn("MarkOtherObjectsAsChangedByUser: full sync locally deleted missing remotely \(object.key)")
                database.delete(object)
            } else {
                DDLogWarn("MarkOtherObjectsAsChangedByUser: full sync marked \(object.key) as changed")
                object.markAsChanged(in: database)
            }
        }
    }
}
