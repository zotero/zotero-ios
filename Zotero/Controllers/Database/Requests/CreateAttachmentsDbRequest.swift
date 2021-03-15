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
    typealias Response = [String]

    let attachments: [Attachment]
    let localizedType: String
    let collections: Set<String>

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> [String] {
        var failedTitles: [String] = []
        self.attachments.forEach { attachment in
            do {
                _ = try CreateAttachmentDbRequest(attachment: attachment, localizedType: self.localizedType,
                                                  collections: self.collections).process(in: database)
            } catch let error {
                DDLogError("CreateAttachmentsDbRequest: could not create attachment - \(error)")
                failedTitles.append(attachment.title)
            }
        }
        return failedTitles
    }
}
