//
//  Predicates.swift
//  Zotero
//
//  Created by Michal Rentka on 27/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct Predicates {

    static func key(_ key: String) -> NSPredicate {
        return NSPredicate(format: "key = %@", key)
    }

    static func key(in keys: [String]) -> NSPredicate {
        return NSPredicate(format: "key IN %@", keys)
    }

    static func key(in keys: Set<String>) -> NSPredicate {
        return NSPredicate(format: "key IN %@", keys)
    }

    static func library(from identifier: LibraryIdentifier) -> NSPredicate {
        switch identifier {
        case .custom(let type):
            return NSPredicate(format: "customLibrary.rawType = %d", type.rawValue)
        case .group(let identifier):
            return NSPredicate(format: "group.identifier = %d", identifier)
        }
    }

    static func keyInLibrary(key: String, libraryId: LibraryIdentifier) -> NSPredicate {
        let keyPredicate = Predicates.key(key)
        let libraryPredicate = Predicates.library(from: libraryId)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [keyPredicate, libraryPredicate])
    }

    static func keysInLibrary(keys: [String], libraryId: LibraryIdentifier) -> NSPredicate {
        let keyPredicate = Predicates.key(in: keys)
        let libraryPredicate = Predicates.library(from: libraryId)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [keyPredicate, libraryPredicate])
    }

    static func keysInLibrary(keys: Set<String>, libraryId: LibraryIdentifier) -> NSPredicate {
        let keyPredicate = Predicates.key(in: keys)
        let libraryPredicate = Predicates.library(from: libraryId)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [keyPredicate, libraryPredicate])
    }

    static func nameInLibrary(name: String, libraryId: LibraryIdentifier) -> NSPredicate {
        let libraryPredicate = Predicates.library(from: libraryId)
        let namePredicate = NSPredicate(format: "name = %@", name)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [namePredicate, libraryPredicate])
    }

    static func changesInLibrary(libraryId: LibraryIdentifier) -> NSPredicate {
        let changePredicate = NSPredicate(format: "rawChangedFields > 0")
        let libraryPredicate = Predicates.library(from: libraryId)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [changePredicate, libraryPredicate])
    }

    static func notSyncState(_ syncState: ObjectSyncState) -> NSPredicate {
        return NSPredicate(format: "rawSyncState != %d", syncState.rawValue)
    }

    static func notSyncState(_ syncState: ObjectSyncState, in libraryId: LibraryIdentifier) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [Predicates.notSyncState(syncState),
                                                                   Predicates.library(from: libraryId)])
    }

    static func items(type: ItemType, notSyncState syncState: ObjectSyncState, trash: Bool? = nil) -> NSPredicate {
        let typePredicate = NSPredicate(format: "rawType = %@", type.rawValue)
        let syncPredicate = Predicates.notSyncState(syncState)
        var predicates: [NSPredicate] = [typePredicate, syncPredicate]
        if let trash = trash {
            let trashPredicate = NSPredicate(format: "trash = %@", NSNumber(booleanLiteral: trash))
            predicates.append(trashPredicate)
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }
}
