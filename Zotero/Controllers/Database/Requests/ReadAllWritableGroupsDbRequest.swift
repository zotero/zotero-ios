//
//  ReadAllWritableGroupsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 23.03.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadAllWritableGroupsDbRequest: DbResponseRequest {
    typealias Response = Results<RGroup>

    var needsWrite: Bool { return false }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> Results<RGroup> {
        return database.objects(RGroup.self).filter(.notSyncState(.dirty))
                                            .filter("canEditMetadata == true")
                                            .sorted(by: [SortDescriptor(keyPath: "orderId", ascending: false),
                                                         SortDescriptor(keyPath: "name")])
    }
}
