//
//  DeleteAllDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 01/04/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct DeleteAllDbRequest: DbRequest {
    var needsWrite: Bool {
        return true
    }

    func process(in database: Realm) throws {
        database.deleteAll()
    }
}
