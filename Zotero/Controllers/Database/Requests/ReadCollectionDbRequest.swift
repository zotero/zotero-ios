//
//  ReadCollectionDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 18/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadCollectionDbRequest: DbResponseRequest {
    typealias Response = RCollection

    let libraryId: LibraryIdentifier
    let key: String

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> RCollection {
        let predicate = Predicates.keyInLibrary(key: self.key, libraryId: self.libraryId)
        guard let collection = database.objects(RCollection.self).filter(predicate).first else {
            throw DbError.objectNotFound
        }
        return collection
    }
}
