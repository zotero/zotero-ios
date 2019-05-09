//
//  DeleteItemDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 02/05/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct DeleteItemDbRequest: DbRequest {
    let item: RItem

    var needsWrite: Bool {
        return false
    }

    func process(in database: Realm) throws {
        
    }
}
