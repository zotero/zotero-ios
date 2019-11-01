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

    var needsWrite: Bool {
        return true
    }

    func process(in database: Realm) throws {
        guard let object = database.objects(RCollection.self).filter(.key(self.key, in: self.libraryId)).first else {
            throw DbError.objectNotFound
        }
        object.items.forEach({ $0.deleted = true })
        object.deleted = true
    }
}
