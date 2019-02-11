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

    let libraryId: Int
    let parentId: String?

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RCollection> {
        let libraryPredicate = NSPredicate(format: "library.identifier = %d", self.libraryId)
        let syncPredicate = NSPredicate(format: "needsSync = false")
        var predicates: [NSPredicate] = [libraryPredicate, syncPredicate]
        if let parentId = self.parentId {
            predicates.append(NSPredicate(format: "parent.identifier = %@", parentId))
        } else {
            predicates.append(NSPredicate(format: "parent = nil"))
        }

        let finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        return database.objects(RCollection.self)
                       .filter(finalPredicate)
                       .sorted(by: [SortDescriptor(keyPath: "name"),
                                    SortDescriptor(keyPath: "identifier")])
    }
}
