//
//  ReadTagsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 09/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadTagPickerTagsDbRequest: DbResponseRequest {
    typealias Response = Results<RTag>

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RTag> {
        return database.objects(RTag.self).filter(.library(with: self.libraryId))
                                          .filter("tags.@count > 0 OR color != %@", "")
    }
}
