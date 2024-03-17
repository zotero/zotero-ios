//
//  CreateTranslatedItemsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 19.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct CreateTranslatedItemsDbRequest: DbRequest {
    let responses: [ItemResponse]
    unowned let schemaController: SchemaController
    unowned let dateParser: DateParser

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        for response in self.responses {
            let response = try StoreItemDbRequest(
                response: response,
                schemaController: self.schemaController,
                dateParser: self.dateParser,
                preferRemoteData: true,
                denyIncorrectCreator: false
            )
            .process(in: database)

            response.item.changeType = .user
            for field in response.item.fields {
                field.changed = true
            }

            var changes: RItemChanges = [.type, .fields, .trash, .tags]
            if !response.item.collections.isEmpty {
                changes.insert(.collections)
            }
            if !response.item.relations.isEmpty {
                changes.insert(.relations)
            }
            if !response.item.creators.isEmpty {
                changes.insert(.creators)
            }
            if !response.item.tags.isEmpty {
                changes.insert(.tags)
            }
            response.item.changes.append(RObjectChange.create(changes: changes))
        }
    }
}
