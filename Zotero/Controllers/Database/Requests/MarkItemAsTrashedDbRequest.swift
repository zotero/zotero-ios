//
//  MarkItemtAsTrashedDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 08/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MarkItemtAsTrashedDbRequest: DbRequest {
    let object: RItem

    var needsWrite: Bool {
        return true
    }

    func process(in database: Realm) throws {
        self.object.trash = true
        self.object.changedFields.insert(.trash)
    }
}
