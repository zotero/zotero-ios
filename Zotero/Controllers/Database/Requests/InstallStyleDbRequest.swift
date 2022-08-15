//
//  InstallStyleDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 10.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct InstallStyleDbRequest: DbResponseRequest {
    typealias Response = Bool

    let identifier: String

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> Bool {
        guard let existing = database.object(ofType: RStyle.self, forPrimaryKey: self.identifier) else { return false }
        existing.installed = true
        return true
    }
}

