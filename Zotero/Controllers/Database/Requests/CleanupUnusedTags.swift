//
//  CleanupUnusedTags.swift
//  Zotero
//
//  Created by Michal Rentka on 24.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct CleanupUnusedTags: DbRequest {
    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let toRemoveTyped = database.objects(RTypedTag.self).filter("item == nil")
        database.delete(toRemoveTyped)

        let toRemoveBase = database.objects(RTag.self).filter("tags.@count == 0 and color == \"\"")
        database.delete(toRemoveBase)
    }
}
