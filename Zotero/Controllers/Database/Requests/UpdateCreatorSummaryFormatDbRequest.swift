//
//  UpdateCreatorSummaryFormatDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 14.01.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct UpdateCreatorSummaryFormatDbRequest: DbRequest {
    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]?

    func process(in database: Realm) throws {
        let itemsWithCreators = database.objects(RItem.self).filter("creators.@count > 0")
        for item in itemsWithCreators {
            item.updateCreatorSummary()
        }
    }
}
