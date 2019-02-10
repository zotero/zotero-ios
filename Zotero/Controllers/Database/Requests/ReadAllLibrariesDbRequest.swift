//
//  ReadAllLibrariesDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadAllLibrariesDbRequest: DbResponseRequest {
    typealias Response = Results<RLibrary>

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RLibrary> {
        return database.objects(RLibrary.self).filter("needsSync = false")
                                              .sorted(by: [SortDescriptor(keyPath: "orderId", ascending: false),
                                                           SortDescriptor(keyPath: "name")])
    }
}
