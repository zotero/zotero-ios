//
//  Predicates.swift
//  Zotero
//
//  Created by Michal Rentka on 27/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct Predicates {
    static func library(from identifier: LibraryIdentifier) -> NSPredicate {
        switch identifier {
        case .custom(let type):
            return NSPredicate(format: "customLibrary.rawType = %d", type.rawValue)
        case .group(let identifier):
            return NSPredicate(format: "group.identifier = %d", identifier)
        }
    }

    static func keyInLibrary(key: String, libraryId: LibraryIdentifier) -> NSPredicate {
        let keyPredicate = NSPredicate(format: "key == %@", key)
        let libraryPredicate = Predicates.library(from: libraryId)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [keyPredicate, libraryPredicate])
    }

    static func keysInLibrary(keys: [String], libraryId: LibraryIdentifier) -> NSPredicate {
        let keyPredicate = NSPredicate(format: "key IN %@", keys)
        let libraryPredicate = Predicates.library(from: libraryId)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [keyPredicate, libraryPredicate])
    }

    static func keysInLibrary(keys: Set<String>, libraryId: LibraryIdentifier) -> NSPredicate {
        let keyPredicate = NSPredicate(format: "key IN %@", keys)
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

    static func needsSync(_ needsSync: Bool, in libraryId: LibraryIdentifier) -> NSPredicate {
        let libraryPredicate = Predicates.library(from: libraryId)
        let syncPredicate = NSPredicate(format: "needsSync = %@", NSNumber(booleanLiteral: needsSync))
        return NSCompoundPredicate(andPredicateWithSubpredicates: [syncPredicate, libraryPredicate])
    }
}
