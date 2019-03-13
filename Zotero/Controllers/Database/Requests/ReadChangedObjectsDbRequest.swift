//
//  ReadChangedObjectsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 11/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadChangedObjectsDbRequest<Obj: UpdatableObject>: DbResponseRequest {
    typealias Response = Results<Obj>

    let libraryId: Int?

    var needsWrite: Bool {
        return false
    }

    func process(in database: Realm) throws -> Results<Obj> {
        var predicates: [NSPredicate] = [NSPredicate(format: "rawChangedFields > 0")]
        if let libraryId = self.libraryId {
            let predicate = NSPredicate(format: "library.identifier = %d", libraryId)
            predicates.append(predicate)
        }
        return database.objects(Obj.self).filter(NSCompoundPredicate(andPredicateWithSubpredicates: predicates))
                                         .sorted(byKeyPath: "dateModified")
    }
}
