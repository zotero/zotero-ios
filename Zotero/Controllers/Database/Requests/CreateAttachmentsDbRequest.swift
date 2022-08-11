//
//  CreateAttachmentsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 21/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct CreateAttachmentsDbRequest: DbResponseRequest {
    typealias Response = [(String, String)]

    let attachments: [Attachment]
    let parentKey: String?
    let localizedType: String
    let collections: Set<String>

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> [(String, String)] {
        guard let libraryId = self.attachments.first?.libraryId else { return [] }

        let parent = self.parentKey.flatMap({ database.objects(RItem.self).filter(.key($0, in: libraryId)).first })
        var failed: [(String, String)] = []

        for attachment in attachments {
            do {
                let attachment = try CreateAttachmentDbRequest(attachment: attachment, parentKey: nil, localizedType: self.localizedType, collections: self.collections, tags: []).process(in: database)
                if let parent = parent {
                    attachment.parent = parent
                    attachment.changedFields.insert(.parent)
                }
            } catch let error {
                DDLogError("CreateAttachmentsDbRequest: could not create attachment - \(error)")
                failed.append((attachment.key, attachment.title))
            }
        }

        return failed
    }
}
