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
        var results = database.objects(RTag.self).filter(.library(with: self.libraryId)).filter("tags.@count > 0")

        switch self.collectionId {
        case .collection(let string):
            results = results.filter(NSPredicate(format: "any tags.item.collections.key = %@", string))
        case .custom(let customType):
            switch customType {
            case .all, .publications: break
            case .unfiled:
                results = results.filter(NSPredicate(format: "any tags.item.collections.@count == 0"))
            case .trash:
                results = results.filter(NSPredicate(format: "any tags.item.trash = true"))
            }
        case .search: break
        }

        if !self.showAutomatic {
            results = results.filter("SUBQUERY(tags, $tag, $tag.type == %@).@count == 0", RTypedTag.Kind.automatic)
        }

        return results
    }
}

struct ReadTagsForItemsDbRequest: DbResponseRequest {
    typealias Response = Results<RTag>

    let itemKeys: Set<String>
    let libraryId: LibraryIdentifier
    let showAutomatic: Bool

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RTag> {
        var results =  database.objects(RTag.self).filter(.library(with: self.libraryId))
                                                  .filter("tags.@count > 0")
        if !self.showAutomatic {
            results = results.filter("SUBQUERY(tags, $tag, $tag.type == %@).@count == 0", RTypedTag.Kind.automatic)
        }
        return results.filter("any tags.item.key in %@", self.itemKeys)
    }
}
