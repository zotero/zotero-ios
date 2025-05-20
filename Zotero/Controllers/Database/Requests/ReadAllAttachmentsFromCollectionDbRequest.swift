//
//  ReadAttachmentsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 22.02.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadAllAttachmentsFromCollectionDbRequest: DbResponseRequest {
    enum Error: Swift.Error {
        case collectionIsTrash
    }

    typealias Response = Results<RItem>

    let collectionId: CollectionIdentifier
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RItem> {
        guard !collectionId.isTrash else { throw Error.collectionIsTrash }

        if Defaults.shared.showSubcollectionItems, case .collection(let key) = collectionId {
            let keys = database.selfAndSubcollectionKeys(for: key, libraryId: libraryId)
            return database.objects(RItem.self).filter(.allAttachments(forCollections: keys, libraryId: libraryId))
        }
        return database.objects(RItem.self).filter(.allAttachments(for: collectionId, libraryId: libraryId))
    }
}
