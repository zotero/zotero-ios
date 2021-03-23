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
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> (Collection?, Library) {
        let library = try ReadLibraryDbRequest(libraryId: self.libraryId).process(in: database)
        var collection: Collection?

        switch self.collectionId {
        case .collection(let key):
            let rCollection = try ReadCollectionDbRequest(libraryId: self.libraryId, key: key).process(in: database)
            collection = Collection(object: rCollection, level: 0, visible: true, hasChildren: false, parentKey: nil, itemCount: 0)
        default: break
        }

        return (collection, library)
    }
}
