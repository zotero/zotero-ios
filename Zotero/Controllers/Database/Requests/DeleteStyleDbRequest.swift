//
//  DeleteStyleDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 04.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct DeleteStyleDbRequest: DbRequest {
    let identifier: String

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        guard let style = database.object(ofType: RStyle.self, forPrimaryKey: self.identifier) else { return }
        database.delete(style)
    }
}
