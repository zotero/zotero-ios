//
//  ReadColoredTagsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 18.04.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadColoredTagsDbRequest: DbResponseRequest {
    typealias Response = Results<RTag>

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RTag> {
        return database.objects(RTag.self).filter(.library(with: self.libraryId))
                                          .filter("color != \"\"")
    }
}
