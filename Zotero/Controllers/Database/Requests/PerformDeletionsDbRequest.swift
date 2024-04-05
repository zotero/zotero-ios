//
//  PerformDeletionsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 21/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct PerformItemDeletionsDbRequest: DbResponseRequest {
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
    let keys: [String]
    let conflictMode: ConflictResolutionMode

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> [(String, String)] {
        let objects = database.objects(RItem.self).filter(.keys(keys, in: libraryId))
        var conflicts: [(String, String)] = []

        for object in objects {
            guard !object.isInvalidated else { continue } // If object is invalidated it has already been removed by some parent before

            switch conflictMode {
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

            case .deleteConflicts:
                break
            }

            object.willRemove(in: database)
            database.delete(object)
        }

        return conflicts
    }
}

struct PerformCollectionDeletionsDbRequest: DbRequest {
    let libraryId: LibraryIdentifier
    let keys: [String]

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let objects = database.objects(RCollection.self).filter(.keys(keys, in: libraryId))
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
}

struct PerformSearchDeletionsDbRequest: DbRequest {
    let libraryId: LibraryIdentifier
    let keys: [String]

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let objects = database.objects(RSearch.self).filter(.keys(keys, in: libraryId))
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
}

struct PerformTagDeletionsDbRequest: DbRequest {
    let libraryId: LibraryIdentifier
    let names: [String]

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let tags = database.objects(RTag.self).filter(.names(names, in: libraryId))
        for tag in tags {
            database.delete(tag.tags)
        }
        database.delete(tags)
    }
}
