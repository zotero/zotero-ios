//
//  PerformDeletionsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 21/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct PerformDeletionsDbRequest: DbResponseRequest {
    typealias Response = [SyncController.Object: [String]]

    let libraryId: LibraryIdentifier
    let response: DeletionsResponse
    let version: Int

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> [SyncController.Object: [String]] {
        var conflicts: [SyncController.Object: [String]] = [:]

        self.delete(objectType: RCollection.self, type: .collection, with: self.response.collections,
                    database: database, conflicts: &conflicts)
        self.delete(objectType: RItem.self, type: .item, with: self.response.items,
                    database: database, conflicts: &conflicts)
        self.delete(objectType: RSearch.self, type: .search, with: self.response.searches,
                    database: database, conflicts: &conflicts)

        let libraryPredicate = Predicates.library(from: self.libraryId)
        let tagNamePredicate = NSPredicate(format: "name IN %@", self.response.tags)
        let tagPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [tagNamePredicate, libraryPredicate])
        let tags = database.objects(RTag.self).filter(tagPredicate)
        // TODO: - Check tags changes
        database.delete(tags)

        switch self.libraryId {
        case .custom(let type):
            let library = database.object(ofType: RCustomLibrary.self, forPrimaryKey: type.rawValue)
            if library?.versions == nil {
                let versions = RVersions()
                database.add(versions)
                library?.versions = versions
            }
            library?.versions?.deletions = self.version

        case .group(let identifier):
            let library = database.object(ofType: RGroup.self, forPrimaryKey: identifier)
            if library?.versions == nil {
                let versions = RVersions()
                database.add(versions)
                library?.versions = versions
            }
            library?.versions?.deletions = self.version
        }

        return conflicts
    }

    private func delete<Obj: UpdatableObject&Syncable>(objectType: Obj.Type, type: SyncController.Object,
                                                       with keys: [String], database: Realm,
                                                       conflicts: inout [SyncController.Object: [String]]) {
        let predicate = Predicates.keysInLibrary(keys: keys, libraryId: self.libraryId)
        let objects = database.objects(Obj.self).filter(predicate)

        for object in objects {
            if object.isChanged {
                if var array = conflicts[type] {
                    array.append(object.key)
                    conflicts[type] = array
                } else {
                    conflicts[type] = [object.key]
                }
            } else {
                object.removeChildren(in: database)
                database.delete(object)
            }
        }
    }
}
