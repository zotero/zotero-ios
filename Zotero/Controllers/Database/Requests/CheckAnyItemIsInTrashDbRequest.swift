//
//  CheckItemsInTrashDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 17.01.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct CheckAnyItemIsInTrashDbRequest: DbResponseRequest {
    typealias Response = Bool

    let libraryId: LibraryIdentifier
    let keys: [String]

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Bool {
        return !database.objects(RItem.self).filter(.keys(self.keys, in: self.libraryId)).filter(.isTrash(true)).isEmpty
    }
}
