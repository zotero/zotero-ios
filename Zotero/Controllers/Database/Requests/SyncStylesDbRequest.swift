//
//  SyncStylesDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 03.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct SyncStylesDbRequest: DbResponseRequest {
    typealias Response = [String]

    let styles: [CitationStyle]

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> [String] {
        var update: [String] = []

        for style in self.styles {
            let rStyle: RStyle

            if let existing = database.object(ofType: RStyle.self, forPrimaryKey: style.identifier) {
                guard existing.updated.timeIntervalSince(style.updated) < 0 else { continue }
                rStyle = existing
            } else {
                rStyle = RStyle()
                rStyle.identifier = style.identifier
                database.add(rStyle)
            }

            rStyle.href = style.href.absoluteString
            rStyle.title = style.title
            rStyle.updated = style.updated
            rStyle.filename = style.filename
            update.append(style.identifier)
        }

        return update
    }
}

