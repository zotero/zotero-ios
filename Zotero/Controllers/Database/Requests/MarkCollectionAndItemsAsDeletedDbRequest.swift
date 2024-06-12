//
//  MarkCollectionAndItemsAsDeletedDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 13/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MarkCollectionAndItemsAsDeletedDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let object = database.objects(RCollection.self).uniqueObject(key: key, libraryId: libraryId) else {
            throw DbError.objectNotFound
        }
        object.items.forEach({
            $0.deleted = true
            $0.changeType = .user
        })
        object.deleted = true
        object.changeType = .user
    }
}
