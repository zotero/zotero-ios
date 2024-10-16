//
//  MarkCollectionsAsTrashedDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 18.07.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MarkCollectionsAsTrashedDbRequest: DbRequest {
    let keys: [String]
    let libraryId: LibraryIdentifier
    let trashed: Bool

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let collections = database.objects(RCollection.self).filter(.keys(self.keys, in: self.libraryId))
        collections.forEach { item in
            item.trash = trashed
            item.changeType = .user
            item.changes.append(RObjectChange.create(changes: RCollectionChanges.trash))
        }
    }
}
