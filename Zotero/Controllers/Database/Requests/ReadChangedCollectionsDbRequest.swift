//
//  ReadChangedCollectionsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 11/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadChangedCollectionsDbRequest: DbResponseRequest {
    typealias Response = Results<RCollection>

    let libraryId: Int

    var needsWrite: Bool {
        return false
    }

    func process(in database: Realm) throws -> Results<RCollection> {
        return database.objects(RCollection.self).filter("library.identifier = %d AND changedFields != ''", libraryId)
                                                 .sorted(byKeyPath: "dateModified")
    }
}
