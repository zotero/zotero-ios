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
        guard let collection = database.objects(RCollection.self).filter(.key(self.key, in: self.libraryId)).first else {
            throw DbError.objectNotFound
        }
        return collection
    }
}
