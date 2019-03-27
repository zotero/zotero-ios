//
//  ReadAllGroupsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 26/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadAllGroupsDbRequest: DbResponseRequest {
    typealias Response = Results<RGroup>

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RGroup> {
        return database.objects(RGroup.self).filter("needsSync = false")
                                            .sorted(by: [SortDescriptor(keyPath: "orderId", ascending: false),
                                                         SortDescriptor(keyPath: "name")])
    }
}
