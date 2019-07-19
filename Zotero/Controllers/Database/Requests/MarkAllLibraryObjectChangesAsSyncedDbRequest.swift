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
        let deletedPredicate = Predicates.deleted(true, in: self.libraryId)
        self.deleteObjects(of: RItem.self, with: deletedPredicate, database: database)
        self.deleteObjects(of: RCollection.self, with: deletedPredicate, database: database)
        self.deleteObjects(of: RSearch.self, with: deletedPredicate, database: database)

        // Mark all local changes as synced
        let changedPredicate = Predicates.changesWithoutDeletions(in: self.libraryId)
        database.objects(RCollection.self).filter(changedPredicate).forEach({ $0.resetChanges() })
        database.objects(RItem.self).filter(changedPredicate).forEach({ $0.resetChanges() })
        database.objects(RSearch.self).filter(changedPredicate).forEach({ $0.resetChanges() })
    }

    private func deleteObjects<Obj: DeletableObject>(of type: Obj.Type, with predicate: NSPredicate, database: Realm) {
        let objects = database.objects(type).filter(predicate)
        objects.forEach { $0.removeChildren(in: database) }
        database.delete(objects)
    }
}
