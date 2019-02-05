//
//  ReadGroupIdsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadGroupIdsDbRequest: DbResponseRequest {
    typealias Response = [Int]

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> [Int] {
        return database.objects(RGroup.self).map({ $0.identifier })
    }
}
