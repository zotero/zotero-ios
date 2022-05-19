//
//  CreateTranslatedItemDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 19.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct CreateTranslatedItemDbRequest: DbRequest {
    let responses: [ItemResponse]
    unowned let schemaController: SchemaController
    unowned let dateParser: DateParser

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        for response in self.responses {
            let (item, _) = try StoreItemDbRequest(response: response, schemaController: self.schemaController, dateParser: self.dateParser, preferRemoteData: true).process(in: database)

            item.changeType = .user
            for field in item.fields {
                field.changed = true
            }

            var changes: RItemChanges = [.type, .fields, .trash]
            if (!item.collections.isEmpty) {
                changes.insert(.collections)
            }
            if (!item.relations.isEmpty) {
                changes.insert(.relations)
            }
            if (!item.creators.isEmpty) {
                changes.insert(.creators)
            }
            if (!item.tags.isEmpty) {
                changes.insert(.tags)
            }
            item.changedFields = changes
        }
    }
}
