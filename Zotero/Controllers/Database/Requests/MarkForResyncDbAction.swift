//
//  MarkForResyncDbAction.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MarkForResyncDbAction<Obj: SyncableObject>: DbRequest {
    let keys: [Obj.IdType]

    var needsWrite: Bool { return true }

    init(keys: [Any]) throws {
        guard let typedKeys = keys as? [Obj.IdType] else { throw DbError.primaryKeyWrongType }
        self.keys = typedKeys
    }

    func process(in database: Realm) throws {
        guard let primaryKeyName = Obj.primaryKey() else { throw DbError.primaryKeyUnavailable }
        let objects = database.objects(Obj.self).filter("\(primaryKeyName) IN %@", self.keys)
        objects.forEach { $0.needsSync = true }
    }
}
