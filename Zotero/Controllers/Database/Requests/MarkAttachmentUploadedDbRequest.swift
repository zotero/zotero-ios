//
//  MarkAttachmentUploadedDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 19/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MarkAttachmentUploadedDbRequest: DbRequest {
    let libraryId: LibraryIdentifier
    let key: String
    let version: Int?

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        guard let attachment = database.objects(RItem.self)
                                       .filter(.key(self.key, in: self.libraryId)).first else { return }
        attachment.attachmentNeedsSync = false
        attachment.changeType = .sync
        if let md5 = attachment.fields.filter(.key(FieldKeys.Item.Attachment.md5)).first?.value {
            attachment.backendMd5 = md5
        }
        if let version = self.version {
            attachment.version = version
        }
    }
}
