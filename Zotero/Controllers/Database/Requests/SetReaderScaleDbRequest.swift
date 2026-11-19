//
//  SetReaderScaleDbRequest.swift
//  Zotero
//
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct SetReaderScaleDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier
    let scale: Double?

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(key, in: libraryId)).first, item.readerScale != scale else { return }
        item.readerScale = scale
    }
}
