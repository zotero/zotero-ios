//
//  CreateAttachmentWithParentDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 20.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift
import CocoaLumberjackSwift

struct CreateAttachmentWithParentDbRequest: DbRequest {
    let attachment: Attachment
    let parentKey: String
    let localizedType: String

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        guard let parentItem = database.objects(RItem.self).filter(.key(self.parentKey, in: self.attachment.libraryId)).first else {
            throw DbError.objectNotFound
        }

        let attachment = try CreateAttachmentDbRequest(attachment: self.attachment, localizedType: self.localizedType, collections: [], tags: []).process(in: database)
        attachment.parent = parentItem
        attachment.changedFields.insert(.parent)
    }
}
