//
//  MarkObjectAsDeletedDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 06/05/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MarkObjectAsDeletedDbRequest: DbRequest {
    let object: DeletableObject

    var needsWrite: Bool {
        return true
    }

    func process(in database: Realm) throws {
        self.object.deleted = true
    }
}
