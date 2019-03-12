//
//  MarkObjectsAsSyncedDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 11/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MarkObjectsAsSyncedDbRequest<Obj: UpdatableObject>: DbRequest {
    let libraryId: Int
    let keys: [String]

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let objects = database.objects(Obj.self)
                              .filter("library.identifier = %d AND key IN %@", self.libraryId, self.keys)
        objects.forEach { object in
            object.resetChanges()
        }
    }
}
