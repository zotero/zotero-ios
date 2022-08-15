//
//  CreateWebDavDeletionsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 29.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct CreateWebDavDeletionsDbRequest: DbResponseRequest {
    typealias Response = Bool

    let keys: [String]
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> Bool {
        var didCreateDeletion = false
        let items = database.objects(RItem.self).filter(.keys(self.keys, in: self.libraryId))

        for item in items {
            if item.rawType == ItemTypes.attachment {
                // Create WebDAV deletion only for attachment items.
                didCreateDeletion = self.createDeletionIfNeeded(for: item.key, database: database) || didCreateDeletion
            } else {
                // Check children of deleted items for attachments.
                let items = item.children.filter(.item(type: ItemTypes.attachment))
                for item in items {
                    didCreateDeletion = self.createDeletionIfNeeded(for: item.key, database: database) || didCreateDeletion
                }
            }
        }

        return didCreateDeletion
    }

    private func createDeletionIfNeeded(for key: String, database: Realm) -> Bool {
        guard database.objects(RWebDavDeletion.self).filter(.key(key, in: self.libraryId)).first == nil else { return false }
        let deletion = RWebDavDeletion()
        deletion.key = key
        deletion.libraryId = self.libraryId
        database.add(deletion)
        return true
    }
}
