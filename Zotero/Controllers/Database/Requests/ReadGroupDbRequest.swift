//
//  ReadGroupDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 14.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadGroupDbRequest: DbResponseRequest {
    typealias Response = RGroup

    let identifier: Int

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> RGroup {
        guard let group = database.object(ofType: RGroup.self, forPrimaryKey: self.identifier) else {
            throw DbError.objectNotFound
        }
        return group
    }
}

