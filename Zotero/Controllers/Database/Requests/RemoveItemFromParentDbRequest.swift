//
//  RemoveItemFromParentDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 25.01.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct RemoveItemFromParentDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool {  return true }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(self.key, in: self.libraryId)).first, item.parent != nil else { return }
        // Update the parent item, so that it's updated in the item list to hide attachment/note marker
        item.parent?.changeType = .user
        item.parent = nil
        item.changes.append(RObjectChange.create(changes: RItemChanges.parent))
        item.changeType = .user
    }
}
