//
//  DeleteGroupDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 01/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct DeleteGroupDbRequest: DbRequest {
    let groupId: Int

    var needsWrite: Bool {
        return true
    }

    func process(in database: Realm) throws {
        guard let object = database.object(ofType: RGroup.self, forPrimaryKey: self.groupId) else { return }

        object.items.forEach { item in
            item.removeChildren(in: database)
        }
        database.delete(object.items)

        object.collections.forEach { collection in
            collection.removeChildren(in: database)
        }
        database.delete(object.collections)

        database.delete(object)
    }
}
