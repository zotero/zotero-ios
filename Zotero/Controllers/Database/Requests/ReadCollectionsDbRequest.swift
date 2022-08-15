//
//  ReadCollectionsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadCollectionsDbRequest: DbResponseRequest {
    typealias Response = Results<RCollection>

    let libraryId: LibraryIdentifier
    let excludedKeys: Set<String>

    var needsWrite: Bool { return false }

    init(libraryId: LibraryIdentifier, excludedKeys: Set<String> = []) {
        self.libraryId = libraryId
        self.excludedKeys = excludedKeys
    }

    func process(in database: Realm) throws -> Results<RCollection> {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [.notSyncState(.dirty, in: self.libraryId),
                                                                            .deleted(false),
                                                                            .key(notIn: self.excludedKeys)])
        return database.objects(RCollection.self).filter(predicate)
    }
}
