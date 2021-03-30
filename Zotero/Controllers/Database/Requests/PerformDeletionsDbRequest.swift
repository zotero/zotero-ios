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
    enum ConflictResolutionMode {
        /// Collect conflicting object keys and return them. Used initially on normal sync to see whether there are conflicts.
        case resolveConflicts
        /// On conflict just delete the object anyway. Used when user confirmed deletion of object.
        case deleteConflicts
        /// On conflict restore original object. Used on full sync when we don't want to remove skipped objects.
        case restoreConflicts
    }

    typealias Response = [(String, String)]

    let libraryId: LibraryIdentifier
    let collections: [String]
    let items: [String]
    let searches: [String]
    let tags: [String]
    let conflictMode: ConflictResolutionMode

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> [(String, String)] {
        self.deleteCollections(with: self.collections, database: database)
        self.deleteSearches(with: self.searches, database: database)
        let conflicts = self.deleteItems(with: self.items, database: database)
        self.deleteTags(with: self.tags, database: database)
        return conflicts
    }

    private func deleteItems(with keys: [String], database: Realm) -> [(String, String)] {
        let objects = database.objects(RItem.self).filter(.keys(keys, in: self.libraryId))

        var conflicts: [(String, String)] = []

        for object in objects {
            guard !object.isInvalidated else { continue } // If object is invalidated it has already been removed by some parent before

            switch self.conflictMode {
            case .resolveConflicts:
                if object.selfOrChildChanged {
                    // If remotely deleted item is changed locally, we need to show CR, so we return keys of such items
                    conflicts.append((object.key, object.displayTitle))
                    continue
                }
            case .restoreConflicts:
                if object.selfOrChildChanged {
                    object.markAsChanged(in: database)
                    continue
                }

            case .deleteConflicts: break
            }

            let wasMainAttachment = object.parent?.mainAttachment?.key == object.key
            let parent = object.parent

            object.willRemove(in: database)
            database.delete(object)

            if wasMainAttachment {
                parent?.updateMainAttachment()
            }
        }

        return conflicts
    }

    private func deleteCollections(with keys: [String], database: Realm) {
        let objects = database.objects(RCollection.self).filter(.keys(keys, in: self.libraryId))

        for object in objects {
            guard !object.isInvalidated else { continue } // If object is invalidated it has already been removed by some parent before

            if object.isChanged {
                // If remotely deleted collection is changed locally, we want to keep the collection, so we mark that
                // this collection is new and it will be reinserted by sync
                object.markAsChanged(in: database)
            } else {
                object.willRemove(in: database)
                database.delete(object)
            }
        }
    }

    private func deleteSearches(with keys: [String], database: Realm) {
        let objects = database.objects(RSearch.self).filter(.keys(keys, in: self.libraryId))

        for object in objects {
            guard !object.isInvalidated else { continue }
            if object.isChanged {
                // If remotely deleted search is changed locally, we want to keep the search, so we mark that
                // this search is new and it will be reinserted by sync
                object.markAsChanged(in: database)
            } else {
                object.willRemove(in: database)
                database.delete(object)
            }
        }
    }

    private func deleteTags(with names: [String], database: Realm) {
        let tags = database.objects(RTag.self).filter(.names(names, in: self.libraryId))
        for tag in tags {
            database.delete(tag.tags)
        }
        database.delete(tags)
    }
}
