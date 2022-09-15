//
//  MarkItemsAsTrashedDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 08/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MarkItemsAsTrashedDbRequest: DbRequest {
    let keys: [String]
    let libraryId: LibraryIdentifier
    let trashed: Bool

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let items = database.objects(RItem.self).filter(.keys(self.keys, in: self.libraryId))
        items.forEach { item in
            item.trash = self.trashed
            item.changeType = .user
            item.changes.append(RObjectChange.create(changes: RItemChanges.trash))
        }
    }
}
