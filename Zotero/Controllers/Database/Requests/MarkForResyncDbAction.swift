//
//  MarkForResyncDbAction.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MarkForResyncDbAction<Obj: SyncableObject&Updatable>: DbRequest {
    let libraryId: LibraryIdentifier
    let keys: [String]

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    init(libraryId: LibraryIdentifier, keys: [String]) {
        self.libraryId = libraryId
        self.keys = keys
    }

    func process(in database: Realm) throws {
        let syncDate = Date()
        var toCreate: [String] = self.keys
        let objects = database.objects(Obj.self).filter(.keys(self.keys, in: self.libraryId))
        
        for object in objects {
            if object.syncState == .synced {
                object.syncState = .outdated
            }
            object.syncRetries += 1
            object.lastSyncDate = syncDate
            object.changeType = .sync
            if let index = toCreate.firstIndex(of: object.key) {
                toCreate.remove(at: index)
            }
        }

        for key in toCreate {
            let object = Obj()
            object.key = key
            object.syncState = .dirty
            object.syncRetries = 1
            object.lastSyncDate = syncDate
            object.libraryId = self.libraryId
            database.add(object)
        }
    }
}

struct MarkGroupForResyncDbAction: DbRequest {
    let identifier: Int

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        if let library = database.object(ofType: RGroup.self, forPrimaryKey: self.identifier) {
            if library.syncState == .synced {
                library.syncState = .outdated
            }
        } else {
            let library = RGroup()
            library.identifier = identifier
            library.syncState = .dirty
            database.add(library)
        }
    }
}
