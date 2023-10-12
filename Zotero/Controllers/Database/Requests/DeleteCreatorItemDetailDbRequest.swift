//
//  DeleteCreatorItemDetailDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 12.10.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct DeleteCreatorItemDetailDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier
    let creatorId: String

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(key, in: libraryId)).first,
            let creator = item.creators.filter("uuid == %@", creatorId).first,
            !creator.isInvalidated
        else { return }
        database.delete(creator)
        item.updateCreatorSummary()
        item.changes.append(RObjectChange.create(changes: RItemChanges.creators))
    }
}
