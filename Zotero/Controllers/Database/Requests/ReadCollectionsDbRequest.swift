//
//  ReadCollectionsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadCollectionsDbRequest: DbResponseRequest {
    typealias Response = Results<RCollection>

    let libraryId: LibraryIdentifier
    let excludedKeys: Set<String>
    let trash: Bool
    let searchTextComponents: [String]

    var needsWrite: Bool { return false }

    init(libraryId: LibraryIdentifier, trash: Bool = false, searchTextComponents: [String] = [], excludedKeys: Set<String> = []) {
        self.libraryId = libraryId
        self.trash = trash
        self.excludedKeys = excludedKeys
        self.searchTextComponents = searchTextComponents
    }

    func process(in database: Realm) throws -> Results<RCollection> {
        var predicates: [NSPredicate] = [
            .notSyncState(.dirty, in: libraryId),
            .deleted(false),
            .isTrash(trash),
            .key(notIn: excludedKeys)
        ]
        if !searchTextComponents.isEmpty {
            for component in searchTextComponents {
                predicates.append(NSPredicate(format: "name contains[c] %@", component))
            }
        }
        return database.objects(RCollection.self).filter(NSCompoundPredicate(andPredicateWithSubpredicates: predicates))
    }
}
