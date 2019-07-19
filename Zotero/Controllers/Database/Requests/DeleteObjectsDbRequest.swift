//
//  DeleteObjectsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 08/05/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct DeleteObjectsDbRequest<Obj: DeletableObject>: DbRequest {
    let keys: [String]
    let libraryId: LibraryIdentifier

    var needsWrite: Bool {
        return true
    }

    func process(in database: Realm) throws {
        let objects = database.objects(Obj.self).filter(Predicates.keys(self.keys, in: self.libraryId))
        objects.forEach { object in
            object.removeChildren(in: database)
        }
        database.delete(objects)
    }
}
