//
//  CheckItemIsChangedDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 18/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct CheckItemIsChangedDbRequest: DbResponseRequest {
    typealias Response = Bool

    let libraryId: LibraryIdentifier
    let key: String

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Bool {
        guard let item = database.objects(RItem.self).uniqueObject(key: key, libraryId: libraryId) else { throw DbError.objectNotFound }
        return item.isChanged
    }
}
