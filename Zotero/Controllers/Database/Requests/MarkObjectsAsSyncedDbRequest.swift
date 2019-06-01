//
//  MarkObjectsAsSyncedDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 11/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MarkObjectsAsSyncedDbRequest<Obj: UpdatableObject&Syncable>: DbRequest {
    let libraryId: LibraryIdentifier
    let keys: [String]
    let version: Int

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let predicate = Predicates.keysInLibrary(keys: self.keys, libraryId: self.libraryId)
        let objects = database.objects(Obj.self).filter(predicate)
        objects.forEach { object in
            if object.version != self.version {
                object.version = self.version
            }
            object.resetChanges()
        }
    }
}
