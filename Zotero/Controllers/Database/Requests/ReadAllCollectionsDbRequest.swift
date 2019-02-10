//
//  ReadAllCollectionsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadAllCollectionsDbRequest: DbResponseRequest {
    typealias Response = Results<RCollection>

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RCollection> {
        return database.objects(RCollection.self).filter("library != nil")
                                                 .filter("needsSync = false")
                                                 .filter("parent == nil OR parent.needsSync = false")
                                                 .sorted(byKeyPath: "library.identifier")
                                                 .sorted(byKeyPath: "parent.identifier")
                                                 .sorted(byKeyPath: "parent.name")
                                                 .sorted(byKeyPath: "identifier")
                                                 .sorted(byKeyPath: "name")
    }
}
