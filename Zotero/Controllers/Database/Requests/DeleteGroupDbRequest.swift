//
//  DeleteGroupDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 01/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct DeleteGroupDbRequest: DbRequest {
    let groupId: Int

    var needsWrite: Bool {
        return true
    }

    func process(in database: Realm) throws {
        let libraryId: LibraryIdentifier = .group(self.groupId)

        let items = database.objects(RItem.self).filter(.library(with: libraryId))
        items.forEach { item in
            item.willRemove(in: database)
        }
        database.delete(items)

        let collections = database.objects(RCollection.self).filter(.library(with: libraryId))
        collections.forEach { collection in
            collection.willRemove(in: database)
        }
        database.delete(collections)

        let searches = database.objects(RSearch.self).filter(.library(with: libraryId))
        searches.forEach { search in
            search.willRemove(in: database)
        }
        database.delete(searches)

        let tags = database.objects(RTag.self).filter(.library(with: libraryId))
        database.delete(tags)

        if let object = database.object(ofType: RGroup.self, forPrimaryKey: self.groupId) {
            database.delete(object)
        }
    }
}
