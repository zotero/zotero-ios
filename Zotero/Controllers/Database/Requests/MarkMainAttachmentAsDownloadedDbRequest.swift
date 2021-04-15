//
//  MarkMainAttachmentAsDownloadedDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 15.04.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct MarkMainAttachmentAsDownloadedDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier
    let downloaded: Bool

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(self.key, in: self.libraryId)).first else {
            DDLogError("MarkMainAttachmentAsDownloadedDbRequest: item not found")
            return
        }
        guard item.parent?.mainAttachment?.key == self.key else { return }
        item.parent?.mainAttachmentDownloaded = self.downloaded
    }
}
