//
//  ReadRecentCollections.swift
//  ZShare
//
//  Created by Michal Rentka on 31.03.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadRecentCollections: DbResponseRequest {
    typealias Response = [CollectionWithLibrary]

    var needsWrite: Bool { return false }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> [CollectionWithLibrary] {
        let collections = database.objects(RCollection.self).sorted(byKeyPath: "lastUsed", ascending: false)

        guard collections.count > 0 else { return [] }

        var recent: [CollectionWithLibrary] = []
        for idx in 0..<(min(collections.count, 5)) {
            let rCollection = collections[idx]

            guard rCollection.lastUsed.timeIntervalSince1970 > 0, let libraryId = rCollection.libraryId else { continue }

            let library = try ReadLibraryDbRequest(libraryId: libraryId).process(in: database)
            let collection = Collection(object: rCollection, level: 0, visible: true, hasChildren: false, parentKey: nil, itemCount: 0)

            recent.append(CollectionWithLibrary(collection: collection, library: library))
        }
        return recent
    }
}

