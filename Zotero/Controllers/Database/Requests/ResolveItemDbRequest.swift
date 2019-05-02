//
//  ResolveItemDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ResolveItemDbRequest: DbResponseRequest {
    typealias Response = RItem?

    let itemRef: ThreadSafeReference<RItem>

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> RItem? {
        database.refresh()
        return database.resolve(self.itemRef)
    }
}
