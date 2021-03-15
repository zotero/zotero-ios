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
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> (RItem, RItem) {
        _ = try StoreItemsDbResponseRequest(responses: [self.item],
                                    schemaController: self.schemaController,
                                    dateParser: self.dateParser,
                                    preferResponseData: true).process(in: database)

        guard let item = database.objects(RItem.self).filter(.key(self.item.key, in: self.attachment.libraryId)).first else {
            throw DbError.objectNotFound
        }

        item.changedFields = [.type, .trash, .collections, .fields, .tags, .creators]
        item.fields.forEach({ $0.changed = true })

        let localizedType = self.schemaController.localized(itemType: ItemTypes.attachment) ?? ""
        let attachment = try CreateAttachmentDbRequest(attachment: self.attachment,
                                                       localizedType: localizedType,
                                                       collections: []).process(in: database)

        attachment.parent = item
        attachment.changedFields.insert(.parent)
        item.updateMainAttachment()

        return (item, attachment)
    }
}
