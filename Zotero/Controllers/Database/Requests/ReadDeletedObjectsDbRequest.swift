//
//  ReadDeletedObjectsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 06/05/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadDeletedObjectsDbRequest<Obj: DeletableObject>: DbResponseRequest {
    typealias Response = Results<Obj>

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<Obj> {
        return database.objects(Obj.self).filter(.deleted(true, in: self.libraryId))
    }
}

struct ReadDeletedLastReadDbRequest: DbResponseRequest {
    typealias Response = Results<RLastReadDate>

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RLastReadDate> {
        // Don't filter last read by library, this setting is always synced to user library, so when it's called for user library, return all changes
        return database.objects(RLastReadDate.self).filter(.deleted(true))
    }
}
