//
//  MarkObjectsAsDeletedDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 06/05/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MarkObjectsAsDeletedDbRequest<Obj: DeletableObject&Updatable>: DbRequest {
    let keys: [String]
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        database.objects(Obj.self).filter(.keys(self.keys, in: self.libraryId)).forEach {
            $0.deleted = true
            $0.changeType = .user
        }
    }
}
