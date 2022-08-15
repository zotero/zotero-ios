//
//  FilterAttachmentsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 28.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct FilterAttachmentsDbRequest: DbResponseRequest {
    typealias Response = [String]

    let keys: [String]
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> [String] {
        return database.objects(RItem.self).filter(.keys(self.keys, in: self.libraryId)).filter(.item(type: ItemTypes.attachment)).map({ $0.key })
    }
}

