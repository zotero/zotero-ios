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
    let version: Int

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        self.deleteCollections(with: self.collections, database: database)
        self.deleteItems(with: self.items, database: database)
    }

    private func deleteItems(with keys: [String], database: Realm) {
        let objects = database.objects(RItem.self).filter(.keys(keys, in: self.libraryId))

        for object in objects {
            guard !object.isInvalidated else { continue } // If object is invalidated it has already been removed by some parent before
            let wasMainAttachment = object.parent?.mainAttachment?.key == object.key
            let parent = object.parent

            object.willRemove(in: database)
            database.delete(object)

            if wasMainAttachment {
                parent?.updateMainAttachment()
            }
        }
    }

    private func deleteCollections(with keys: [String], database: Realm) {
        let objects = database.objects(RCollection.self).filter(.keys(keys, in: self.libraryId))

        for object in objects {
            // BETA: - for beta we prefer all remote changes, so if something was deleted remotely we always delete it
            // locally, even if the user changed it
//            if object.isChanged {
                // If remotely deleted collection is changed locally, we want to keep the collection, so we mark that
                // this collection is new and it will be reinserted by sync
//                object.changedFields = .all
//            } else {
                object.willRemove(in: database)
                database.delete(object)
//            }
        }
    }
}
