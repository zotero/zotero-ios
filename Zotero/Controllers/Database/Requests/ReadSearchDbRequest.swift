//
//  ReadSearchDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 06/05/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadSearchDbRequest: DbResponseRequest {
    typealias Response = RSearch

    let libraryId: LibraryIdentifier
    let key: String

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> RSearch {
        guard let search = database.objects(RSearch.self).uniqueObject(key: key, libraryId: libraryId) else {
            throw DbError.objectNotFound
        }
        return search
    }
}
