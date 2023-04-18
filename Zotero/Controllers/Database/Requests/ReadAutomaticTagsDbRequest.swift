//
//  ReadAutomaticTagsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 18.04.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadAutomaticTagsDbRequest: DbResponseRequest {
    typealias Response = Results<RTypedTag>

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RTypedTag> {
        return database.objects(RTypedTag.self).filter(.typedTagLibrary(with: self.libraryId)).filter("type = %@", RTypedTag.Kind.automatic)
    }
}
