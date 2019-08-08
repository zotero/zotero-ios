//
//  MarkItemtAsTrashedDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 08/08/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MarkItemtAsTrashedDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier
    let trashed: Bool

    var needsWrite: Bool {
        return true
    }

    func process(in database: Realm) throws {
        guard let object = database.objects(RItem.self).filter(Predicates.key(self.key, in: self.libraryId)).first else {
            throw DbError.objectNotFound
        }
        object.trash = self.trashed
        object.changedFields.insert(.trash)
    }
}
