//
//  SetCollectionCollapsedDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 15.03.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct SetCollectionCollapsedDbRequest: DbRequest {
    let collapsed: Bool
    let identifier: CollectionIdentifier
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        switch self.identifier {
        case .collection(let key):
            guard let collection = database.objects(RCollection.self).filter(.key(key, in: self.libraryId)).first, collection.collapsed != self.collapsed else { return }
            collection.collapsed = self.collapsed
        case .search: break // TODO
        case .custom: break
        }
    }
}

struct SetCollectionsCollapsedDbRequest: DbRequest {
    let identifiers: Set<CollectionIdentifier>
    let collapsed: Bool
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        let keys = identifiers.compactMap({ $0.key })
        guard !keys.isEmpty else { return }

        switch self.identifiers.first! {
        case .collection:
            for collection in database.objects(RCollection.self).filter(.keys(keys, in: self.libraryId)) {
                collection.collapsed = self.collapsed
            }
        case .search: break // TODO
        case .custom: break
        }
    }
}
