//
//  DeleteAllWebDavDeletionsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 01.11.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct DeleteAllWebDavDeletionsDbRequest: DbRequest {
    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        database.delete(database.objects(RWebDavDeletion.self))
    }
}

