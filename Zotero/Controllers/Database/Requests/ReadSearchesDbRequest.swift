//
//  ReadSearchesDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 26/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadSearchesDbRequest: DbResponseRequest {
    typealias Response = Results<RSearch>

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> Results<RSearch> {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [.notSyncState(.dirty, in: self.libraryId),
                                                                            .deleted(false)])
        return database.objects(RSearch.self).filter(predicate)
                                             .sorted(byKeyPath: "name")
    }
}
