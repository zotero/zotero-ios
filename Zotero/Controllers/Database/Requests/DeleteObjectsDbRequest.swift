//
//  DeleteObjectsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 08/05/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct DeleteObjectsDbRequest<Obj: DeletableObject>: DbRequest {
    let keys: [String]
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        let objects = database.objects(Obj.self).filter(.keys(self.keys, in: self.libraryId))
        for object in objects {
            guard !object.isInvalidated else { continue }
            object.willRemove(in: database)
        }
        database.delete(objects)
    }
}
