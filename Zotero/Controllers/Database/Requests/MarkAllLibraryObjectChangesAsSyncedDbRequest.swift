//
//  MarkAllLibraryObjectChangesAsSyncedDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 02/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MarkAllLibraryObjectChangesAsSyncedDbRequest: DbRequest {
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        // Delete all locally deleted objects
        let deletedPredicate = NSPredicate.deleted(true, in: self.libraryId)
        self.deleteObjects(of: RItem.self, with: deletedPredicate, database: database)
        self.deleteObjects(of: RCollection.self, with: deletedPredicate, database: database)
        self.deleteObjects(of: RSearch.self, with: deletedPredicate, database: database)

        // Mark all local changes as synced
        let changedPredicate = NSPredicate.changesWithoutDeletions(in: self.libraryId)
        for object in database.objects(RCollection.self).filter(changedPredicate) {
            object.deleteAllChanges(database: database)
        }
        for object in database.objects(RItem.self).filter(changedPredicate) {
            object.deleteAllChanges(database: database)
        }
        for object in database.objects(RSearch.self).filter(changedPredicate) {
            object.deleteAllChanges(database: database)
        }
    }

    private func deleteObjects<Obj: DeletableObject>(of type: Obj.Type, with predicate: NSPredicate, database: Realm) {
        let objects = database.objects(type).filter(predicate)
        for object in objects {
            guard !object.isInvalidated else { continue }
            object.willRemove(in: database)
        }
        database.delete(objects)
    }
}
