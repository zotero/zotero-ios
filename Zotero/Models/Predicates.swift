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
        return NSPredicate(format: "key in %@", keys)
    }

    static func key(in keys: Set<String>) -> NSPredicate {
        return NSPredicate(format: "key in %@", keys)
    }

    static func key(notIn keys: [String]) -> NSPredicate {
        return NSPredicate(format: "not key in %@", keys)
    }

    static func name(_ name: String) -> NSPredicate {
        return NSPredicate(format: "name = %@", name)
    }

    static func name(notIn names: [String]) -> NSPredicate {
        return NSPredicate(format: "not name in %@", names)
    }

    static func library(with identifier: LibraryIdentifier) -> NSPredicate {
        switch identifier {
        case .custom(let type):
            return NSPredicate(format: "customLibrary.rawType = %d", type.rawValue)
        case .group(let identifier):
            return NSPredicate(format: "group.identifier = %d", identifier)
        }
    }

    static func key(_ key: String, in libraryId: LibraryIdentifier) -> NSPredicate {
        let keyPredicate = Predicates.key(key)
        let libraryPredicate = Predicates.library(with: libraryId)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [keyPredicate, libraryPredicate])
    }

    static func keys(_ keys: [String], in libraryId: LibraryIdentifier) -> NSPredicate {
        let keyPredicate = Predicates.key(in: keys)
        let libraryPredicate = Predicates.library(with: libraryId)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [keyPredicate, libraryPredicate])
    }

    static func keys(_ keys: Set<String>, in libraryId: LibraryIdentifier) -> NSPredicate {
        let keyPredicate = Predicates.key(in: keys)
        let libraryPredicate = Predicates.library(with: libraryId)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [keyPredicate, libraryPredicate])
    }

    static func name(_ name: String, in libraryId: LibraryIdentifier) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [Predicates.name(name),
                                                                   Predicates.library(with: libraryId)])
    }

    static var changed: NSPredicate {
        return NSPredicate(format: "rawChangedFields > 0")
    }

    static var notChanged: NSPredicate {
        return NSPredicate(format: "rawChangedFields = 0")
    }

    static var attachmentChanged: NSPredicate {
        return NSPredicate(format: "attachmentNeedsSync = true")
    }

    static var changedOrDeleted: NSPredicate {
        return NSCompoundPredicate(orPredicateWithSubpredicates: [Predicates.changed, Predicates.deleted(true)])
    }

    static func changesWithoutDeletions(in libraryId: LibraryIdentifier) -> NSPredicate {
        let changePredicate = Predicates.changed
        let libraryPredicate = Predicates.library(with: libraryId)
        let deletedPredicate = Predicates.deleted(false)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [changePredicate, libraryPredicate, deletedPredicate])
    }

    static func itemChangesWithoutDeletions(in libraryId: LibraryIdentifier) -> NSPredicate {
        let fieldChangePredicate = Predicates.changed
        let attachmentChangePredicate = Predicates.attachmentChanged
        let changePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [fieldChangePredicate, attachmentChangePredicate])
        let libraryPredicate = Predicates.library(with: libraryId)
        let deletedPredicate = Predicates.deleted(false)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [changePredicate, libraryPredicate, deletedPredicate])

    }

    static func changesOrDeletions(in libraryId: LibraryIdentifier) -> NSPredicate {
        let changePredicate = Predicates.changed
        let deletedPredicate = Predicates.deleted(true)
        let changesPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [changePredicate, deletedPredicate])
        let libraryPredicate = Predicates.library(with: libraryId)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [changesPredicate, libraryPredicate])
    }

    static func syncState(_ syncState: ObjectSyncState) -> NSPredicate {
        return NSPredicate(format: "rawSyncState = %d", syncState.rawValue)
    }

    static func notSyncState(_ syncState: ObjectSyncState) -> NSPredicate {
        return NSPredicate(format: "rawSyncState != %d", syncState.rawValue)
    }

    static func notSyncState(_ syncState: ObjectSyncState, in libraryId: LibraryIdentifier) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [Predicates.notSyncState(syncState),
                                                                   Predicates.library(with: libraryId)])
    }

    static func deleted(_ deleted: Bool) -> NSPredicate {
        return NSPredicate(format: "deleted = %@", NSNumber(value: deleted))
    }

    static func deleted(_ deleted: Bool, in libraryId: LibraryIdentifier) -> NSPredicate {
        let deletedPredicate = Predicates.deleted(deleted)
        let libraryPredicate = Predicates.library(with: libraryId)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [libraryPredicate, deletedPredicate])
    }

    static func items(type: String, notSyncState syncState: ObjectSyncState, trash: Bool? = nil) -> NSPredicate {
        let typePredicate = Predicates.item(type: type)
        let syncPredicate = Predicates.notSyncState(syncState)
        var predicates: [NSPredicate] = [typePredicate, syncPredicate]
        if let trash = trash {
            let trashPredicate = NSPredicate(format: "trash = %@", NSNumber(booleanLiteral: trash))
            predicates.append(trashPredicate)
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    static var attachmentNeedsUpload: NSPredicate {
        return NSPredicate(format: "attachmentNeedsSync = true")
    }

    static func item(type: String) -> NSPredicate {
        return NSPredicate(format: "rawType = %@", type)
    }

    static func itemsNotChangedAndNeedUpload(in libraryId: LibraryIdentifier) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [Predicates.notChanged,
                                                                   Predicates.attachmentNeedsUpload,
                                                                   Predicates.item(type: ItemTypes.attachment),
                                                                   Predicates.library(with: libraryId)])
    }

    static func itemSearch(for text: String) -> NSPredicate {
        let titlePredicate = NSPredicate(format: "title contains[c] %@", text)

        let creatorFullNamePredicate = NSPredicate(format: "ANY creators.name contains[c] %@", text)
        let creatorFirstNamePredicate = NSPredicate(format: "ANY creators.firstName contains[c] %@", text)
        let creatorLastNamePredicate = NSPredicate(format: "ANY creators.lastName contains[c] %@", text)
        let creatorPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [creatorFullNamePredicate,
                                                                                  creatorFirstNamePredicate,
                                                                                  creatorLastNamePredicate])

        let tagPredicate = NSPredicate(format: "ANY tags.name contains[c] %@", text)

        return NSCompoundPredicate(orPredicateWithSubpredicates: [titlePredicate,
                                                                  creatorPredicate,
                                                                  tagPredicate])
    }
}
