//
//  FixChildItemsWithCollectionsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 02.12.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct FixChildItemsWithCollectionsDbRequest: DbRequest {
    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let items = database.objects(RItem.self).filter("parent != nil AND collections.@count > 0")

        for item in items {
            for collection in item.collections {
                guard let index = collection.items.index(of: item) else { continue }
                collection.items.remove(at: index)
            }

            item.changes.append(RObjectChange.create(changes: RItemChanges.collections))
            item.changeType = .user
        }
    }
}
