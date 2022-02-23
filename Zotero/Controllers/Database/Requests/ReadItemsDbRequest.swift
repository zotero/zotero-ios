//
//  ReadItemsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 11/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadItemsDbRequest: DbResponseRequest {
    typealias Response = Results<RItem>

    let collectionId: CollectionIdentifier
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> Results<RItem> {
        if Defaults.shared.showSubcollectionItems,
           case .collection(let key) = self.collectionId {
            let keys = self.selfAndSubcollectionKeys(for: key, in: database)
            return database.objects(RItem.self).filter(.items(forCollections: keys, libraryId: self.libraryId))
        }
        return database.objects(RItem.self).filter(.items(for: self.collectionId, libraryId: self.libraryId))
    }

    private func selfAndSubcollectionKeys(for key: String, in database: Realm) -> Set<String> {
        var keys: Set<String> = [key]
        let children = database.objects(RCollection.self).filter(.parentKey(key, in: self.libraryId))
        for child in children {
            keys.formUnion(self.selfAndSubcollectionKeys(for: child.key, in: database))
        }
        return keys
    }
}

struct ReadItemsWithKeysDbRequest: DbResponseRequest {
    typealias Response = Results<RItem>

    let keys: Set<String>
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> Results<RItem> {
        return database.objects(RItem.self).filter(.keys(self.keys, in: self.libraryId))
    }
}
