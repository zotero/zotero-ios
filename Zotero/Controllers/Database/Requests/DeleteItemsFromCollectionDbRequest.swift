//
//  DeleteItemsFromCollectionDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 22/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct DeleteItemsFromCollectionDbRequest: DbRequest {
    let collectionKey: String
    let itemKeys: Set<String>
    let libraryId: LibraryIdentifier

    var needsWrite: Bool {
        return true
    }

    func process(in database: Realm) throws {
        guard let collection = database.objects(RCollection.self)
                                       .filter(Predicates.key(self.collectionKey, in: self.libraryId)).first else {
            return
        }
        let items = database.objects(RItem.self).filter(Predicates.keys(self.itemKeys, in: self.libraryId))

        items.forEach { item in
            if let index = item.collections.index(of: collection) {
                item.collections.remove(at: index)
                item.changedFields.insert(.collections)
            }
        }
    }
}
