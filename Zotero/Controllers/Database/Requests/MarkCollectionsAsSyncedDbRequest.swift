//
//  MarkCollectionsAsSyncedDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 11/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MarkCollectionsAsSyncedDbRequest: DbRequest {
    let libraryId: Int
    let keys: [String]

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let objects = database.objects(RCollection.self)
                              .filter("library.identifier = %d AND keys = %@", self.libraryId, self.keys)
        objects.forEach { collection in
            collection.changedFields = ""
        }
    }
}
