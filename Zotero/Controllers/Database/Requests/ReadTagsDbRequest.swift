//
//  ReadTagsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 09/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadTagPickerTagsDbRequest: DbResponseRequest {
    typealias Response = Results<RTag>

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RTag> {
        return database.objects(RTag.self).filter(.library(with: self.libraryId))
                                          .filter("tags.@count > 0 OR color != %@", "")
    }
}

struct ReadTagsWithNamesDbRequest: DbResponseRequest {
    typealias Response = Results<RTag>

    let names: Set<String>
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RTag> {
        return database.objects(RTag.self).filter(.names(self.names, in: self.libraryId))
    }
}

struct ReadColoredTagsDbRequest: DbResponseRequest {
    typealias Response = Results<RTag>

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RTag> {
        return database.objects(RTag.self).filter(.library(with: self.libraryId))
                                          .filter("color != \"\"")
    }
}

struct ReadTagsForCollectionDbRequest: DbResponseRequest {
    typealias Response = Results<RTag>

    let collectionId: CollectionIdentifier
    let libraryId: LibraryIdentifier
    let showAutomatic: Bool

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RTag> {
        var predicates: [NSPredicate] = [.typedTagLibrary(with: self.libraryId)]

        switch self.collectionId {
        case .collection(let string):
            predicates.append(NSPredicate(format: "any item.collections.key = %@", string))
        case .custom(let customType):
            switch customType {
            case .all, .publications: break
            case .unfiled:
                predicates.append(NSPredicate(format: "item.collections.@count == 0"))
            case .trash:
                predicates.append(NSPredicate(format: "item.trash = true"))
            }
        case .search: break
        }

        if !self.showAutomatic {
            // Don't apply this filter to colored tags
            predicates.append(NSPredicate(format: "type = %d or tag.color != \"\"", RTypedTag.Kind.manual.rawValue))
        }

        let typedTags = database.objects(RTypedTag.self).filter(NSCompoundPredicate(andPredicateWithSubpredicates: predicates))

        var names: Set<String> = []
        for tag in typedTags {
            guard let name = tag.tag?.name else { continue }
            names.insert(name)
        }
        return database.objects(RTag.self).filter(.library(with: self.libraryId)).filter("name in %@", names)
    }
}

struct ReadTagsForItemsDbRequest: DbResponseRequest {
    typealias Response = Results<RTag>

    let itemKeys: Set<String>
    let libraryId: LibraryIdentifier
    let showAutomatic: Bool

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RTag> {
        var predicates: [NSPredicate] = [.typedTagLibrary(with: self.libraryId)]

        if !self.showAutomatic {
            // Don't apply this filter to colored tags
            predicates.append(NSPredicate(format: "type = %d or tag.color != \"\"", RTypedTag.Kind.manual.rawValue))
        }

        predicates.append(NSPredicate(format: "item.key in %@", self.itemKeys))

        let typedTags = database.objects(RTypedTag.self).filter(NSCompoundPredicate(andPredicateWithSubpredicates: predicates))

        var names: Set<String> = []
        for tag in typedTags {
            guard let name = tag.tag?.name else { continue }
            names.insert(name)
        }
        return database.objects(RTag.self).filter(.library(with: self.libraryId)).filter("name in %@", names)
    }
}

struct ReadAutomaticTagsDbRequest: DbResponseRequest {
    typealias Response = Results<RTypedTag>

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RTypedTag> {
        return database.objects(RTypedTag.self).filter(.typedTagLibrary(with: self.libraryId)).filter("type = %@", RTypedTag.Kind.automatic)
    }
}
