//
//  CountObjectsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 04.04.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct CountObjectsDbRequest<Obj: Object>: DbResponseRequest {
    typealias Response = Int

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Int {
        return database.objects(Obj.self).count
    }
}
