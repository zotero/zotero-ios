//
//  CreateCollectionDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 17/04/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct CreateCollectionDbRequest: DbRequest {
    let libraryId: LibraryIdentifier
    let key: String
    let name: String
    let parentKey: String?

    var needsWrite: Bool {
        return true
    }

    func process(in database: Realm) throws {
        let collection = RCollection()
        collection.key = key
        collection.name = name
        collection.changedFields = .all
        collection.syncState = .synced

        if let key = self.parentKey {
            let predicate = Predicates.keyInLibrary(key: key, libraryId: self.libraryId)
            collection.parent = database.objects(RCollection.self).filter(predicate).first
        }

        switch self.libraryId {
        case .custom(let type):
            let library = database.object(ofType: RCustomLibrary.self, forPrimaryKey: type.rawValue)
            collection.customLibrary = library
        case .group(let identifier):
            let group = database.object(ofType: RGroup.self, forPrimaryKey: identifier)
            collection.group = group
        }

        database.add(collection)
    }
}
