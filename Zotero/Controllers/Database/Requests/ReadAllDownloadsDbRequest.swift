//
//  ReadAllDownloadsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 20.12.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadAllDownloadsDbRequest: DbResponseRequest {
    typealias Response = Results<RDownload>

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RDownload> {
        return database.objects(RDownload.self)
    }
}
