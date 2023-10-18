//
//  ReadItemDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 10/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadItemDbRequest: DbResponseRequest {
    typealias Response = RItem

    let libraryId: LibraryIdentifier
    let key: String

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> RItem {
        guard let item = database.objects(RItem.self).filter(.key(self.key, in: self.libraryId)).first else {
            throw DbError.objectNotFound
        }
        return item
    }
}

struct ReadItemGloballyDbRequest: DbResponseRequest {
    typealias Response = RItem

    let key: String

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> RItem {
        guard let item = database.objects(RItem.self).filter(.key(key)).first else {
            throw DbError.objectNotFound
        }
        return item
    }
}
