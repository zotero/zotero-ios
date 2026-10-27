//
//  SetCollectionShowsInCarPlayDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 14.10.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct SetCollectionShowsInCarPlayDbRequest: DbRequest {
    let showsInCarPlay: Bool
    let key: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let collection = database.objects(RCollection.self).uniqueObject(key: key, libraryId: libraryId), collection.showsInCarPlay != showsInCarPlay else { return }
        collection.showsInCarPlay = showsInCarPlay
    }
}
