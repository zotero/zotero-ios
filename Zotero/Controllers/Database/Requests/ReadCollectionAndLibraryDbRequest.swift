//
//  ReadCollectionAndLibraryDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 23.03.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadCollectionAndLibraryDbRequest: DbResponseRequest {
    typealias Response = (Collection?, Library)

    let collectionId: CollectionIdentifier
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> (Collection?, Library) {
        let library = try ReadLibraryDbRequest(libraryId: self.libraryId).process(in: database)

        switch self.collectionId {
        case .collection(let key):
            let rCollection = try ReadCollectionDbRequest(libraryId: self.libraryId, key: key).process(in: database)
            let collection = Collection(object: rCollection, itemCount: 0)
            return (collection, library)

        case .custom(let type):
            let collection = Collection(custom: type)
            return (collection, library)

        default:
            return (nil, library)
        }
    }
}
