//
//  MarkFileAsDownloadedDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 15.04.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct MarkFileAsDownloadedDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier
    let downloaded: Bool

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(self.key, in: self.libraryId)).first else {
            DDLogError("MarkFileAsDownloadedDbRequest: item not found")
            return
        }
        guard item.rawType == ItemTypes.attachment && item.fileDownloaded != self.downloaded else { return }
        item.fileDownloaded = self.downloaded
    }
}

struct MarkItemsFilesAsNotDownloadedDbRequest: DbRequest {
    let keys: Set<String>
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        let items = database.objects(RItem.self).filter(.keys(self.keys, in: self.libraryId)).filter(.item(type: ItemTypes.attachment)).filter(.file(downloaded: true))
        for item in items {
            guard !item.attachmentNeedsSync else { continue }
            item.fileDownloaded = false
        }
    }
}

struct MarkLibraryFilesAsNotDownloadedDbRequest: DbRequest {
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        let items = database.objects(RItem.self).filter(.library(with: self.libraryId)).filter(.item(type: ItemTypes.attachment)).filter(.file(downloaded: true))
        for item in items {
            guard !item.attachmentNeedsSync else { continue }
            item.fileDownloaded = false
        }
    }
}

struct MarkAllFilesAsNotDownloadedDbRequest: DbRequest {
    var needsWrite: Bool { return true }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws {
        let items = database.objects(RItem.self).filter(.item(type: ItemTypes.attachment)).filter(.file(downloaded: true))
        for item in items {
            guard !item.attachmentNeedsSync else { continue }
            item.fileDownloaded = false
        }
    }
}
