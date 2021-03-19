//
//  Predicates.swift
//  Zotero
//
//  Created by Michal Rentka on 27/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

extension NSPredicate {
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

    static func key(notIn keys: Set<String>) -> NSPredicate {
        return NSPredicate(format: "not key in %@", keys)
    }

    static func key(_ key: String, in libraryId: LibraryIdentifier) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [.key(key), .library(with: libraryId)])
    }

    static func keys(_ keys: [String], in libraryId: LibraryIdentifier) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [.key(in: keys),
                                                                   .library(with: libraryId)])
    }

    static func keys(_ keys: Set<String>, in libraryId: LibraryIdentifier) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [.key(in: keys),
                                                                   .library(with: libraryId)])
    }

    static func tagName(_ name: String) -> NSPredicate {
        return NSPredicate(format: "tag.name = %@", name)
    }

    static func tagName(in names: Set<String>) -> NSPredicate {
        return NSPredicate(format: "tag.name in %@", names)
    }

    static func tagName(notIn names: [String]) -> NSPredicate {
        return NSPredicate(format: "not tag.name in %@", names)
    }

    static func name(_ name: String) -> NSPredicate {
        return NSPredicate(format: "name = %@", name)
    }

    static func name(in names: [String]) -> NSPredicate {
        return NSPredicate(format: "name in %@", names)
    }

    static func name(in names: Set<String>) -> NSPredicate {
        return NSPredicate(format: "name in %@", names)
    }

    static func name(notIn names: [String]) -> NSPredicate {
        return NSPredicate(format: "not name in %@", names)
    }

    static func name(notIn names: Set<String>) -> NSPredicate {
        return NSPredicate(format: "not name in %@", names)
    }

    static func name(_ name: String, in libraryId: LibraryIdentifier) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [.name(name),
                                                                   .library(with: libraryId)])
    }

    static func names(_ names: [String], in libraryId: LibraryIdentifier) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [.name(in: names),
                                                                   .library(with: libraryId)])
    }

    static func names(_ names: Set<String>, in libraryId: LibraryIdentifier) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [.name(in: names),
                                                                   .library(with: libraryId)])
    }

    static func library(with identifier: LibraryIdentifier) -> NSPredicate {
        switch identifier {
        case .custom(let type):
            return NSPredicate(format: "customLibraryKey = %d", type.rawValue)
        case .group(let identifier):
            return NSPredicate(format: "groupKey = %d", identifier)
        }
    }

    static func parentLibrary(with identifier: LibraryIdentifier) -> NSPredicate {
        switch identifier {
        case .custom(let type):
            return NSPredicate(format: "parent.customLibraryKey = %d", type.rawValue)
        case .group(let identifier):
            return NSPredicate(format: "parent.groupKey = %d", identifier)
        }
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

    static var userChanges: NSPredicate {
        return NSPredicate(format: "rawChangeType = %d", UpdatableChangeType.user.rawValue)
    }

    static func changes(in libraryId: LibraryIdentifier) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [.changed,
                                                                   .library(with: libraryId)])
    }

    static func changesWithoutDeletions(in libraryId: LibraryIdentifier) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [.changed,
                                                                   .library(with: libraryId),
                                                                   .deleted(false)])
    }

    static func itemChangesWithoutDeletions(in libraryId: LibraryIdentifier) -> NSPredicate {
        let changePredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [.changed, .attachmentChanged])
        return NSCompoundPredicate(andPredicateWithSubpredicates: [changePredicate,
                                                                   .library(with: libraryId),
                                                                   .deleted(false)])

    }

    static func changesOrDeletions(in libraryId: LibraryIdentifier) -> NSPredicate {
        let changesPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [.changed, .deleted(true)])
        return NSCompoundPredicate(andPredicateWithSubpredicates: [changesPredicate,
                                                                   .library(with: libraryId)])
    }

    static func syncState(_ syncState: ObjectSyncState) -> NSPredicate {
        return NSPredicate(format: "rawSyncState = %d", syncState.rawValue)
    }

    static func notSyncState(_ syncState: ObjectSyncState) -> NSPredicate {
        return NSPredicate(format: "rawSyncState != %d", syncState.rawValue)
    }

    static func notSyncState(_ syncState: ObjectSyncState, in libraryId: LibraryIdentifier) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [.notSyncState(syncState),
                                                                   .library(with: libraryId)])
    }

    static func deleted(_ deleted: Bool) -> NSPredicate {
        return NSPredicate(format: "deleted = %@", NSNumber(value: deleted))
    }

    static func deleted(_ deleted: Bool, in libraryId: LibraryIdentifier) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [.library(with: libraryId),
                                                                   .deleted(deleted)])
    }

    static func isTrash(_ trash: Bool) -> NSPredicate {
        return NSPredicate(format: "trash = %@", NSNumber(booleanLiteral: trash))
    }

    static func items(for type: ItemFetchType, libraryId: LibraryIdentifier) -> NSPredicate {
        var predicates: [NSPredicate] = [.library(with: libraryId),
                                         .notSyncState(.dirty),
                                         .deleted(false)]

        var isTrash = false

        switch type {
        case .all, .search: break
        case .trash:
            isTrash = true
        case .publications:
            predicates.append(NSPredicate(format: "ANY collections.key = %@", "unknown"))
        case .collection(let key, _):
            predicates.append(NSPredicate(format: "ANY collections.key = %@", key))
        }
        
        if !isTrash {
            predicates.append(NSPredicate(format: "parent = nil"))
        }
        predicates.append(NSPredicate(format: "trash = %@", NSNumber(booleanLiteral: isTrash)))

        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    static func items(type: String, notSyncState syncState: ObjectSyncState, trash: Bool? = nil) -> NSPredicate {
        var predicates: [NSPredicate] = [.item(type: type), .notSyncState(syncState)]
        if let trash = trash {
            predicates.append(.isTrash(trash))
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
        return NSCompoundPredicate(andPredicateWithSubpredicates: [.notChanged,
                                                                   .attachmentNeedsUpload,
                                                                   .item(type: ItemTypes.attachment),
                                                                   .library(with: libraryId)])
    }

    static func itemSearch(for text: String) -> NSPredicate {
        let titlePredicate = NSPredicate(format: "displayTitle contains[c] %@", text)

        let creatorFullNamePredicate = NSPredicate(format: "ANY creators.name contains[c] %@", text)
        let creatorFirstNamePredicate = NSPredicate(format: "ANY creators.firstName contains[c] %@", text)
        let creatorLastNamePredicate = NSPredicate(format: "ANY creators.lastName contains[c] %@", text)
        let creatorPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [creatorFullNamePredicate,
                                                                                  creatorFirstNamePredicate,
                                                                                  creatorLastNamePredicate])

        let tagPredicate = NSPredicate(format: "ANY tags.tag.name contains[c] %@", text)

        return NSCompoundPredicate(orPredicateWithSubpredicates: [titlePredicate,
                                                                  creatorPredicate,
                                                                  tagPredicate])
    }

    static func linkType(_ type: LinkType) -> NSPredicate {
        return NSPredicate(format: "type = %@", type.rawValue)
    }

    static func containsField(key: String) -> NSPredicate {
        return NSPredicate(format: "ANY fields.key = %@", key)
    }

    static func parent(_ parentKey: String, in libraryId: LibraryIdentifier) -> NSPredicate {
        let libraryPredicate: NSPredicate = .parentLibrary(with: libraryId)
        let parentPredicate: NSPredicate = NSPredicate(format: "parent.key = %@", parentKey)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [libraryPredicate, parentPredicate])
    }

    static func parentKey(_ parentKey: String, in library: LibraryIdentifier) -> NSPredicate {
        let libraryPredicate: NSPredicate = .library(with: library)
        let parentPredicate: NSPredicate = .parentKey(parentKey)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [libraryPredicate, parentPredicate])
    }

    static func parentKey(_ parentKey: String) -> NSPredicate {
        return NSPredicate(format: "parentKey = %@", parentKey)
    }

    static var parentKeyNil: NSPredicate {
        return NSPredicate(format: "parentKey == nil")
    }

    static func groupId(_ identifier: Int) -> NSPredicate {
        return NSPredicate(format: "identifier == %d", identifier)
    }
}
