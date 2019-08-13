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
    typealias Response = [String]

    let libraryId: LibraryIdentifier
    let response: DeletionsResponse
    let version: Int

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> [String] {
        self.deleteCollections(with: self.response.collections, database: database)
        self.deleteSearches(with: self.response.searches, database: database)
        let conflicts = self.deleteItems(with: self.response.items, database: database)
        self.deleteTags(with: self.response.tags, database: database)

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

    private func deleteItems(with keys: [String], database: Realm) -> [String] {
        let predicate = Predicates.keys(keys, in: self.libraryId)
        let objects = database.objects(RItem.self).filter(predicate)

        var conflicts: [String] = []

        for object in objects {
            if object.isChanged {
                // If remotely deleted item is changed locally, we need to show CR, so we return keys of such items
                conflicts.append(object.key)
            } else {
                object.removeChildren(in: database)
                database.delete(object)
            }
        }

        return conflicts
    }

    private func deleteCollections(with keys: [String], database: Realm) {
        let predicate = Predicates.keys(keys, in: self.libraryId)
        let objects = database.objects(RCollection.self).filter(predicate)

        for object in objects {
            if object.isChanged {
                // If remotely deleted collection is changed locally, we want to keep the collection, so we mark that
                // this collection is new and it will be reinserted by sync
                object.changedFields = .all
            } else {
                object.removeChildren(in: database)
                database.delete(object)
            }
        }
    }

    private func deleteSearches(with keys: [String], database: Realm) {
        let predicate = Predicates.keys(keys, in: self.libraryId)
        let objects = database.objects(RSearch.self).filter(predicate)

        for object in objects {
            if object.isChanged {
                // If remotely deleted search is changed locally, we want to keep the search, so we mark that
                // this search is new and it will be reinserted by sync
                object.changedFields = .all
            } else {
                object.removeChildren(in: database)
                database.delete(object)
            }
        }
    }

    private func deleteTags(with names: [String], database: Realm) {
        let libraryPredicate = Predicates.library(with: self.libraryId)
        let tagNamePredicate = NSPredicate(format: "name IN %@", names)
        let tagPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [tagNamePredicate, libraryPredicate])
        let tags = database.objects(RTag.self).filter(tagPredicate)
        for object in tags {
            if object.rawChangedFields > 0 {
                // If remotely deleted tag is changed locally, we want to keep the tag, so we mark that
                // this tag is new and it will be reinserted by sync
                object.changedFields = .all
            } else {
                database.delete(object)
            }
        }
        database.delete(tags)
    }
}
