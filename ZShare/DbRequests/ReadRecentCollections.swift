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
    typealias Response = [RecentData]

    private static let limit = 5
    let excluding: (String, LibraryIdentifier)?

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> [RecentData] {
        let collections = database.objects(RCollection.self).sorted(byKeyPath: "lastUsed", ascending: false)

        guard collections.count > 0 else { return [] }

        var recent: [RecentData] = []
        for rCollection in collections {
            guard rCollection.lastUsed.timeIntervalSince1970 > 0, let libraryId = rCollection.libraryId else { break }

            let library = try ReadLibraryDbRequest(libraryId: libraryId).process(in: database)

            if let (key, libraryId) = self.excluding, rCollection.key == key && library.identifier == libraryId {
                continue
            }

            let collection = Collection(object: rCollection, itemCount: 0)

            recent.append(RecentData(collection: collection, library: library, isRecent: true))

            if recent.count == ReadRecentCollections.limit {
                break
            }
        }
        return recent
    }
}
