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

    let type: ItemFetchType
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> Results<RItem> {
        if Defaults.shared.showSubcollectionItems,
           case .collection(let key, _) = self.type {
            let keys = self.selfAndSubcollectionKeys(for: key, in: database)
            return database.objects(RItem.self).filter(.itemsForCollections(keys: keys, libraryId: self.libraryId))
        }
        return database.objects(RItem.self).filter(.items(for: self.type, libraryId: self.libraryId))
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
