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
    let parentKey: String?
    let trash: Bool

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RItem> {
        var predicates: [NSPredicate] = [.library(with: self.libraryId),
                                         .notSyncState(.dirty),
                                         .deleted(false)]
        if let collectionId = self.collectionKey {
            predicates.append(NSPredicate(format: "ANY collections.key = %@", collectionId))
        }
        if let key = self.parentKey {
            if key.isEmpty {
                predicates.append(NSPredicate(format: "parent = nil"))
            } else {
                predicates.append(NSPredicate(format: "parent.key = %@", key))
            }
        }
        predicates.append(NSPredicate(format: "trash = %@", NSNumber(booleanLiteral: self.trash)))

        let finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        return database.objects(RItem.self)
                       .filter(finalPredicate)
    }
}
