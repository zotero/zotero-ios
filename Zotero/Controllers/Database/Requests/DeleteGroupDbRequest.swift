//
//  DeleteGroupDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 01/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct DeleteGroupDbRequest: DbRequest {
    let groupId: Int

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        let libraryId: LibraryIdentifier = .group(self.groupId)

        self.deleteObjects(of: RItem.self, with: .library(with: libraryId), database: database)
        self.deleteObjects(of: RCollection.self, with: .library(with: libraryId), database: database)
        self.deleteObjects(of: RSearch.self, with: .library(with: libraryId), database: database)

        let tags = database.objects(RTag.self).filter(.library(with: libraryId))
        for tag in tags {
            guard !tag.isInvalidated else { continue }
            database.delete(tag.tags)
        }
        database.delete(tags)

        if let object = database.object(ofType: RGroup.self, forPrimaryKey: self.groupId) {
            guard !object.isInvalidated else { return }
            database.delete(object)
        }
    }

    private func deleteObjects<Obj: DeletableObject>(of type: Obj.Type, with predicate: NSPredicate, database: Realm) {
        let objects = database.objects(type).filter(predicate)
        for object in objects {
            guard !object.isInvalidated else { continue }
            object.willRemove(in: database)
        }
        database.delete(objects)
    }
}
