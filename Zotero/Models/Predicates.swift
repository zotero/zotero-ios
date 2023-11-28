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

    static func key(notIn keys: [String], in libraryId: LibraryIdentifier) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [.library(with: libraryId), .key(notIn: keys)])
    }

    static func key(_ key: String, andBaseKey baseKey: String) -> NSPredicate {
        return NSPredicate(format: "key = %@ AND baseKey = %@", key, baseKey)
    }

    static func baseKey(_ baseKey: String) -> NSPredicate {
        return NSPredicate(format: "baseKey = %@", baseKey)
    }

    static func tagName(_ name: String) -> NSPredicate {
        return NSPredicate(format: "tag.name = %@", name)
    }

    static func tagName(in names: [String]) -> NSPredicate {
        return NSPredicate(format: "tag.name in %@", names)
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

    static func typedTagLibrary(with identifier: LibraryIdentifier) -> NSPredicate {
        switch identifier {
        case .custom(let type):
            return NSPredicate(format: "tag.customLibraryKey = %d", type.rawValue)

        case .group(let identifier):
            return NSPredicate(format: "tag.groupKey = %d", identifier)
        }
    }

    static var changed: NSPredicate {
        return NSPredicate(format: "changes.@count > 0")
    }

    static var notChanged: NSPredicate {
        return NSPredicate(format: "changes.@count = 0")
    }

    static var changesNotPaused: NSPredicate {
        return NSPredicate(format: "changesSyncPaused == false")
    }

    static var attachmentChanged: NSPredicate {
        return NSPredicate(format: "attachmentNeedsSync = true")
    }

    static var changedByUser: NSPredicate {
        return NSPredicate(format: "changeType = %d", UpdatableChangeType.user.rawValue)
    }

    static var userChanges: NSPredicate {
        let changed = NSCompoundPredicate(orPredicateWithSubpredicates: [.changed, .deleted(true)])
        return NSCompoundPredicate(andPredicateWithSubpredicates: [.changedByUser, changed])
    }

    static var itemUserChanges: NSPredicate {
        let changed = NSCompoundPredicate(orPredicateWithSubpredicates: [.changed, .attachmentChanged, .deleted(true)])
        return NSCompoundPredicate(andPredicateWithSubpredicates: [.changedByUser, changed, .changesNotPaused])
    }

    static var pageIndexUserChanges: NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [.changedByUser, .changed])
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
        return NSPredicate(format: "syncState = %d", syncState.rawValue)
    }

    static func notSyncState(_ syncState: ObjectSyncState) -> NSPredicate {
        return NSPredicate(format: "syncState != %d", syncState.rawValue)
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

    private static func baseItemPredicates(isTrash: Bool, libraryId: LibraryIdentifier) -> [NSPredicate] {
        var predicates: [NSPredicate] = [.library(with: libraryId), .notSyncState(.dirty), .deleted(false), .isTrash(isTrash)]
        if !isTrash {
            predicates.append(NSPredicate(format: "parent = nil"))
        }
        return predicates
    }

    static func items(for collectionId: CollectionIdentifier, libraryId: LibraryIdentifier) -> NSPredicate {
        var predicates = self.baseItemPredicates(isTrash: collectionId.isTrash, libraryId: libraryId)

        switch collectionId {
        case .collection(let key):
            predicates.append(NSPredicate(format: "any collections.key = %@", key))

        case .custom(let type):
            switch type {
            case .unfiled:
                predicates.append(NSPredicate(format: "collections.@count == 0"))
            case .all, .publications, .trash: break
            }
        case .search: break
        }

        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    static func items(forCollections keys: Set<String>, libraryId: LibraryIdentifier) -> NSPredicate {
        var predicates = self.baseItemPredicates(isTrash: false, libraryId: libraryId)
        predicates.append(NSPredicate(format: "any collections.key in %@", keys))
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    static func items(type: String, notSyncState syncState: ObjectSyncState, trash: Bool? = nil) -> NSPredicate {
        var predicates: [NSPredicate] = [.item(type: type), .notSyncState(syncState)]
        if let trash = trash {
            predicates.append(.isTrash(trash))
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    private static func baseAllAttachmentsPredicates(for libraryId: LibraryIdentifier) -> [NSPredicate] {
        return [.library(with: libraryId), .notSyncState(.dirty), .deleted(false), .isTrash(false), .item(type: ItemTypes.attachment)]
    }

    static func allAttachments(for collectionId: CollectionIdentifier, libraryId: LibraryIdentifier) -> NSPredicate {
        var predicates: [NSPredicate] = self.baseAllAttachmentsPredicates(for: libraryId)

        switch collectionId {
        case .collection(let key):
            let selfInCollection = NSPredicate(format: "any collections.key = %@", key)
            let parentInCollection = NSPredicate(format: "any parent.collections.key = %@", key)
            predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [selfInCollection, parentInCollection]))
        case .search, .custom: break
        }

        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    static func allAttachments(forCollections keys: Set<String>, libraryId: LibraryIdentifier) -> NSPredicate {
        var predicates: [NSPredicate] = self.baseAllAttachmentsPredicates(for: libraryId)

        let selfInCollections = NSPredicate(format: "any collections.key in %@", keys)
        let parentInCollections = NSPredicate(format: "any parent.collections.key in %@", keys)
        predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [selfInCollections, parentInCollections]))

        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    static var attachmentNeedsUpload: NSPredicate {
        return NSPredicate(format: "attachmentNeedsSync = true")
    }

    static func item(type: String) -> NSPredicate {
        return NSPredicate(format: "rawType = %@", type)
    }

    static func item(notTypeIn itemTypes: Set<String>) -> NSPredicate {
        return NSPredicate(format: "not rawType in %@", itemTypes)
    }

    static func itemsNotChangedAndNeedUpload(in libraryId: LibraryIdentifier) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [.notChanged,
                                                                   .attachmentNeedsUpload,
                                                                   .item(type: ItemTypes.attachment),
                                                                   .library(with: libraryId)])
    }

    static func itemSearch(for components: [String]) -> NSPredicate {
        let predicates = components.map({ self.itemSearchSubpredicates(for: $0) })
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    private static func itemSearchSubpredicates(for text: String) -> NSPredicate {
        let keyPredicate = NSPredicate(format: "key == %@", text)
        let childrenKeyPredicate = NSPredicate(format: "any children.key == %@", text)
        // TODO: - ideally change back to "==" if Realm issue is fixed
        let childrenChildrenKeyPredicate = NSPredicate(format: "any children.children.key contains %@", text)
        let contentPredicate = NSPredicate(format: "htmlFreeContent contains[c] %@", text)
        let childrenContentPredicate = NSPredicate(format: "any children.htmlFreeContent contains[c] %@", text)
        let childrenChildrenContentPredicate = NSPredicate(format: "any children.children.htmlFreeContent contains[c] %@", text)
        let titlePredicate = NSPredicate(format: "sortTitle contains[c] %@", text)
        let childrenTitlePredicate = NSPredicate(format: "any children.sortTitle contains[c] %@", text)
        let creatorFullNamePredicate = NSPredicate(format: "any creators.name contains[c] %@", text)
        let creatorFirstNamePredicate = NSPredicate(format: "any creators.firstName contains[c] %@", text)
        let creatorLastNamePredicate = NSPredicate(format: "any creators.lastName contains[c] %@", text)
        let tagPredicate = NSPredicate(format: "any tags.tag.name contains[c] %@", text)
        let childrenTagPredicate = NSPredicate(format: "any children.tags.tag.name contains[c] %@", text)
        let childrenChildrenTagPredicate = NSPredicate(format: "any children.children.tags.tag.name contains[c] %@", text)
        let fieldsPredicate = NSPredicate(format: "any fields.value contains[c] %@", text)
        let childrenFieldsPredicate = NSPredicate(format: "any children.fields.value contains[c] %@", text)
        let childrenChildrenFieldsPredicate = NSPredicate(format: "any children.children.fields.value contains[c] %@", text)

        var predicates = [
            keyPredicate,
            titlePredicate,
            contentPredicate,
            creatorFullNamePredicate,
            creatorFirstNamePredicate,
            creatorLastNamePredicate,
            tagPredicate,
            childrenKeyPredicate,
            childrenTitlePredicate,
            childrenContentPredicate,
            childrenTagPredicate,
            childrenChildrenKeyPredicate,
            childrenChildrenContentPredicate,
            childrenChildrenTagPredicate,
            fieldsPredicate,
            childrenFieldsPredicate,
            childrenChildrenFieldsPredicate
        ]

        if let int = Int(text) {
            let yearPredicate = NSPredicate(format: "parsedYear == %d", int)
            predicates.insert(yearPredicate, at: 3)
        }

        return NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
    }

    static func linkType(_ type: LinkType) -> NSPredicate {
        return NSPredicate(format: "type = %@", type.rawValue)
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

    static func file(downloaded: Bool) -> NSPredicate {
        return NSPredicate(format: "fileDownloaded = %@", NSNumber(booleanLiteral: downloaded))
    }

    static var baseTagsToDelete: NSPredicate {
        let count = NSPredicate(format: "tag.tags.@count == 1")
        let special = NSPredicate(format: "tag.color == %@ or tag.emojiGroup == nil", "")
        return NSCompoundPredicate(andPredicateWithSubpredicates: [special, count])
    }
}
