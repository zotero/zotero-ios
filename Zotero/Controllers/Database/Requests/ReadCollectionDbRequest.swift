//
//  ReadCollectionDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 18/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadRCollectionDbRequest: DbResponseRequest {
    typealias Response = RCollection

    let libraryId: LibraryIdentifier
    let key: String

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> RCollection {
        guard let collection = database.objects(RCollection.self).uniqueObject(key: key, libraryId: libraryId) else {
            throw DbError.objectNotFound
        }
        return collection
    }
}

struct ReadCollectionDbRequest: DbResponseRequest {
    typealias Response = Collection?

    let collectionId: CollectionIdentifier
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Collection? {
        switch collectionId {
        case .collection(let key):
            let rCollection = try ReadRCollectionDbRequest(libraryId: libraryId, key: key).process(in: database)
            return Collection(object: rCollection, itemCount: 0)

        case .custom(let type):
            return Collection(custom: type)

        default:
            return nil
        }
    }
}
