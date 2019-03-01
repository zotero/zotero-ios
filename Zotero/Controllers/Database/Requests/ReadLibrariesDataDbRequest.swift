//
//  ReadLibrariesDataDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadLibrariesDataDbRequest: DbResponseRequest {
    typealias Response = [(Int, String, RVersions?)]

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> [(Int, String, RVersions?)] {
        return database.objects(RLibrary.self).map({ ($0.identifier, $0.name, $0.versions) })
    }
}
