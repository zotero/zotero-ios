//
//  StoreStyleDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 04.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct StoreStyleDbRequest: DbRequest {
    let style: RemoteCitationStyle

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        let rStyle: RStyle

        if let existing = database.object(ofType: RStyle.self, forPrimaryKey: self.style.name) {
            rStyle = existing
        } else {
            rStyle = RStyle()
            rStyle.identifier = self.style.name
            database.add(rStyle)
        }

        rStyle.href = self.style.href.absoluteString
        rStyle.title = self.style.title
        rStyle.updated = self.style.updated
    }
}

