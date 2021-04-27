//
//  ReadAllDownloadedItems.swift
//  Zotero
//
//  Created by Michal Rentka on 27.04.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadAllDownloadedItems: DbResponseRequest {
    typealias Response = Results<RItem>

    var needsWrite: Bool { return false }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> Results<RItem> {
        return database.objects(RItem.self).filter(.item(type: ItemTypes.attachment)).filter(.file(downloaded: true))
    }
}
