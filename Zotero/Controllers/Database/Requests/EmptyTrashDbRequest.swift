//
//  EmptyTrashDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 24.03.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct EmptyTrashDbRequest: DbRequest {
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        database.objects(RItem.self).filter(.items(for: .custom(.trash), libraryId: libraryId)).forEach {
            $0.deleted = true
            $0.changeType = .user
        }
        database.objects(RCollection.self).filter(.trashedCollections(in: libraryId)).forEach {
            $0.deleted = true
            $0.changeType = .user
        }
    }
}
