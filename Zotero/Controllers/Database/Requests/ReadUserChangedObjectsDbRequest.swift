//
//  ReadUserChangedObjectsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 14/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadUserChangedObjectsDbRequest<Obj: UpdatableObject>: DbResponseRequest {
    typealias Response = Results<Obj>

    var needsWrite: Bool { return false }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> Results<Obj> {
        return database.objects(Obj.self).filter(.userChanges)
    }
}
