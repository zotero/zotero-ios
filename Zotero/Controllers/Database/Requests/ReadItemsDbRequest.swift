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

    let libraryId: Int
    let collectionId: String?
    let parentId: String?

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RItem> {
        let libraryPredicate = NSPredicate(format: "library.identifier = %d", self.libraryId)
        let syncPredicate = NSPredicate(format: "needsSync = false")
        var predicates: [NSPredicate] = [libraryPredicate, syncPredicate]
        if let collectionId = self.collectionId {
            predicates.append(NSPredicate(format: "ANY collections.identifier = %@", collectionId))
        }
        if let parentId = self.parentId {
            predicates.append(NSPredicate(format: "parent.identifier = %@", parentId))
        } else {
            predicates.append(NSPredicate(format: "parent = nil"))
        }

        let finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        return database.objects(RItem.self)
                       .filter(finalPredicate)
                       .sorted(by: [SortDescriptor(keyPath: "title"),
                                    SortDescriptor(keyPath: "identifier")])
    }
}
