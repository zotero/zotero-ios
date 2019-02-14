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

    let libraryId: Int

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RCollection> {
        let libraryPredicate = NSPredicate(format: "library.identifier = %d", self.libraryId)
        let syncPredicate = NSPredicate(format: "needsSync = false")
        let finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [libraryPredicate, syncPredicate])
        return database.objects(RCollection.self)
                       .filter(finalPredicate)
    }
}
