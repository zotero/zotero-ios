//
//  ReorderCreatorsItemDetailDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 12.10.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReorderCreatorsItemDetailDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier
    let ids: [String]

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(key, in: libraryId)).first else { return }
        for (orderId, uuid) in ids.enumerated() {
            item.creators.filter("uuid == %@", uuid).first?.orderId = orderId
        }
    }
}
