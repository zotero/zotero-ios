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
    typealias Response = Results<RItem>

    let collectionId: CollectionIdentifier
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> Results<RItem> {
        if Defaults.shared.showSubcollectionItems,
           case .collection(let key) = self.collectionId {
            let keys = self.selfAndSubcollectionKeys(for: key, in: database)
            return database.objects(RItem.self).filter(.itemsForCollections(keys: keys, libraryId: self.libraryId))
        }
        return database.objects(RItem.self).filter(.items(for: self.collectionId, libraryId: self.libraryId))
    }

    private func selfAndSubcollectionKeys(for key: String, in database: Realm) -> [String] {
        var keys: [String] = [key]
        let children = database.objects(RCollection.self).filter(.parentKey(key, in: self.libraryId))
        for child in children {
            keys.append(child.key)
            keys.append(contentsOf: self.selfAndSubcollectionKeys(for: child.key, in: database))
        }
        return keys
    }
}
