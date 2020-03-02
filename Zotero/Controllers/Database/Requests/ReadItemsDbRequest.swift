//
//  ReadItemsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 11/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadItemsDbRequest: DbResponseRequest {
    typealias Response = Results<RItem>

    let libraryId: LibraryIdentifier
    let collectionKey: String?
    let withoutParentOnly: Bool
    let trash: Bool

    init(type: ItemFetchType, libraryId: LibraryIdentifier) {
        self.libraryId = libraryId

        // TODO: - implement publications and search fetching
        switch type {
        case .all:
            self.collectionKey = nil
            self.trash = false
            self.withoutParentOnly = true
        case .trash:
            self.collectionKey = nil
            self.trash = true
            self.withoutParentOnly = false
        case .search:
            self.collectionKey = nil
            self.trash = false
            self.withoutParentOnly = true
        case .publications:
            self.collectionKey = "unknown"
            self.trash = false
            self.withoutParentOnly = true
        case .collection(let key, _):
            self.collectionKey = key
            self.trash = false
            self.withoutParentOnly = true
        }
    }

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RItem> {
        var predicates: [NSPredicate] = [.library(with: self.libraryId),
                                         .notSyncState(.dirty),
                                         .deleted(false)]
        if let collectionId = self.collectionKey {
            predicates.append(NSPredicate(format: "ANY collections.key = %@", collectionId))
        }
        if self.withoutParentOnly {
            predicates.append(NSPredicate(format: "parent = nil"))
        }
        predicates.append(NSPredicate(format: "trash = %@", NSNumber(booleanLiteral: self.trash)))

        let finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        return database.objects(RItem.self)
                       .filter(finalPredicate)
    }
}
