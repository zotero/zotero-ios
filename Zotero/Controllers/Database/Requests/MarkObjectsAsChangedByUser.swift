//
//  MarkObjectsAsChangedByUser.swift
//  Zotero
//
//  Created by Michal Rentka on 11.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

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

struct MarkOtherObjectsAsChangedByUser<Obj: Syncable&Deletable&UpdatableObject>: DbRequest {
    let libraryId: LibraryIdentifier
    let keys: [String]

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        let objects = database.objects(Obj.self).filter(.library(with: self.libraryId))

        for object in objects {
            guard !object.isInvalidated && !self.keys.contains(object.key) else { continue }
            if object.deleted {
                database.delete(object)
            } else {
                object.markAsChanged(in: database)
            }
        }
    }
}
