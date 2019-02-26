//
//  PerformDeletionsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 21/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct PerformDeletionsDbRequest: DbRequest {
    let libraryId: Int
    let response: DeletionsResponse
    let version: Int

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let collections = database.objects(RCollection.self)
                                  .filter("library.identifier = %d AND key IN %@", self.libraryId,
                                                                                   self.response.collections)
        collections.forEach { collection in
            collection.removeChildren(in: database)
        }
        database.delete(collections)

        let items = database.objects(RItem.self)
                            .filter("library.identifier = %d AND key IN %@", self.libraryId, self.response.items)
        items.forEach { item in
            item.removeChildren(in: database)
        }
        database.delete(items)

        let searches = database.objects(RSearch.self)
                               .filter("library.identifier = %d AND key IN %@", self.libraryId, self.response.searches)
        database.delete(searches)

        let tags = database.objects(RTag.self)
                           .filter("library.identifier = %d AND name IN %@", self.libraryId, self.response.tags)
        database.delete(tags)

        let library = database.object(ofType: RLibrary.self, forPrimaryKey: self.libraryId)
        if library?.versions == nil {
            let versions = RVersions()
            database.add(versions)
            library?.versions = versions
        }
        library?.versions?.deletions = self.version
    }
}
