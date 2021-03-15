//
//  UpdateItemLocaleDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 07/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct UpdateItemLocaleDbRequest: DbRequest {
    let locale: SchemaLocale

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        let items = database.objects(RItem.self).filter(.notSyncState(.dirty))
                                                .filter(.deleted(false))
        items.forEach { item in
            if let localized = self.locale.itemTypes[item.rawType] {
                if item.localizedType != localized {
                    item.localizedType = localized
                    item.changeType = .sync
                }
            }
        }
    }
}
