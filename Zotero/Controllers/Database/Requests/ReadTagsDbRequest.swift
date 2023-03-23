//
//  ReadTagsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 09/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadTagsDbRequest: DbResponseRequest {
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

struct ReadFilterTagsDbRequest: DbResponseRequest {
    typealias Response = Results<RTag>

    let libraryId: LibraryIdentifier
    let collectionId: CollectionIdentifier
    let selectedNames: Set<String>

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RTag> {
        var conditions: [NSPredicate] = [.library(with: self.libraryId), NSPredicate(format: "tags.@count > 0")]

        switch self.collectionId {
        case .collection(let string):
            conditions.append(NSPredicate(format: "any tags.item.collections.key = %@", string))
        case .custom(let customType):
            switch customType {
            case .all, .publications: break
            case .unfiled:
                conditions.append(NSPredicate(format: "any tags.item.collections.@count == 0"))
            case .trash:
                conditions.append(NSPredicate(format: "any tags.item.trash = true"))
            }
        case .search: break
        }

        if !self.selectedNames.isEmpty {
            conditions.append(NSPredicate(format: "any tags.item.tags.tag.name in %@", self.selectedNames))
        }

        return database.objects(RTag.self).filter(NSCompoundPredicate(andPredicateWithSubpredicates: conditions))
    }
}
