//
//  ReadAllCustomLibrariesDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadAllCustomLibrariesDbRequest: DbResponseRequest {
    typealias Response = Results<RCustomLibrary>

    var needsWrite: Bool { return false }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> Results<RCustomLibrary> {
        return database.objects(RCustomLibrary.self).sorted(byKeyPath: "orderId")
    }
}
