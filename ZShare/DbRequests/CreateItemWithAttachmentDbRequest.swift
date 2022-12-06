//
//  CreateItemWithAttachmentDbRequest.swift
//  ZShare
//
//  Created by Michal Rentka on 03/01/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct CreateItemWithAttachmentDbRequest: DbResponseRequest {
    typealias Response = (RItem, RItem)

    let item: ItemResponse
    let attachment: Attachment
    unowned let schemaController: SchemaController
    unowned let dateParser: DateParser

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> (RItem, RItem) {
        _ = try StoreItemsDbResponseRequest(responses: [self.item],
                                            schemaController: self.schemaController,
                                            dateParser: self.dateParser,
                                            preferResponseData: true).process(in: database)

        guard let item = database.objects(RItem.self).filter(.key(self.item.key, in: self.attachment.libraryId)).first else {
            throw DbError.objectNotFound
        }

        let changes: RItemChanges = [.type, .trash, .collections, .fields, .tags, .creators]
        item.changes.append(RObjectChange.create(changes: changes))
        item.fields.forEach({ $0.changed = true })

        let localizedType = self.schemaController.localized(itemType: ItemTypes.attachment) ?? ""
        let attachment = try CreateAttachmentDbRequest(attachment: self.attachment,
                                                       parentKey: nil,
                                                       localizedType: localizedType,
                                                       includeAccessDate: self.attachment.hasUrl,
                                                       collections: [],
                                                       tags: []).process(in: database)

        attachment.parent = item
        attachment.changes.append(RObjectChange.create(changes: RItemChanges.parent))

        return (item, attachment)
    }
}
