//
//  CreateBackendItemDbRequest.swift
//  ZShare
//
//  Created by Michal Rentka on 14/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct CreateBackendItemDbRequest: DbResponseRequest {
    typealias Response = RItem

    let item: ItemResponse
    let schemaController: SchemaController

    var needsWrite: Bool {
        return true
    }

    func process(in database: Realm) throws -> RItem {
        guard let libraryId = self.item.library.libraryId else {
            throw DbError.objectNotFound
        }

        _ = try StoreItemsDbRequest(response: [self.item], schemaController: self.schemaController, preferRemoteData: true).process(in: database)

        guard let item = database.objects(RItem.self).filter(.key(self.item.key, in: libraryId)).first else {
            throw DbError.objectNotFound
        }

        item.changedFields = [.type, .trash, .collections, .fields, .tags, .creators]
        item.fields.forEach({ $0.changed = true })

        return item
    }
}
