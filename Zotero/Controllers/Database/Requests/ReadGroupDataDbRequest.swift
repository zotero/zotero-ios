//
//  ReadGroupDataDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadGroupDataDbRequest: DbResponseRequest {
    typealias Response = [(Int, RVersions?)]

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> [(Int, RVersions?)] {
        return database.objects(RLibrary.self).map({ ($0.identifier, $0.versions) })
    }
}
