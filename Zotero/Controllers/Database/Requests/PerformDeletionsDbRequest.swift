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

    let libraryId: Int
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

        let tags = database.objects(RTag.self)
                           .filter("library.identifier = %d AND name IN %@", self.libraryId, self.response.tags)
        // TODO: - Check tags changes
        database.delete(tags)

        let library = database.object(ofType: RLibrary.self, forPrimaryKey: self.libraryId)
        if library?.versions == nil {
            let versions = RVersions()
            database.add(versions)
            library?.versions = versions
        }
        library?.versions?.deletions = self.version

        return conflicts
    }

    private func delete<Obj: UpdatableObject&Syncable>(objectType: Obj.Type, type: SyncController.Object,
                                                       with keys: [String], database: Realm,
                                                       conflicts: inout [SyncController.Object: [String]]) {
        let objects = database.objects(Obj.self)
                              .filter("library.identifier = %d AND key IN %@", self.libraryId, keys)
        objects.forEach { object in
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
