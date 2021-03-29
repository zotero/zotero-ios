//
//  InitializeCustomLibrariesDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct InitializeCustomLibrariesDbRequest: DbResponseRequest {
    typealias Response = Bool

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> Bool {
        let (isNew, object) = try database.autocreatedObject(ofType: RCustomLibrary.self, forPrimaryKey: RCustomLibraryType.myLibrary.rawValue)

        guard isNew else { return false }

        object.orderId = 1
        let versions = RVersions()
        database.add(versions)
        object.versions = versions

        return true
    }
}
