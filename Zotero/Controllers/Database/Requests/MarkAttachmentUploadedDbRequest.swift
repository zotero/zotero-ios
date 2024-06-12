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

    func process(in database: Realm) throws {
        guard let attachment = database.objects(RItem.self).uniqueObject(key: key, libraryId: libraryId) else { return }
        attachment.attachmentNeedsSync = false
        attachment.changeType = .syncResponse
        if let md5 = attachment.fields.filter(.key(FieldKeys.Item.Attachment.md5)).first?.value {
            attachment.backendMd5 = md5
        }
        if let version = self.version {
            attachment.version = version
        }
        if let parent = attachment.parent {
            // This is to mitigate the issue in item detail screen (ItemDetailActionHandler.shouldReloadData) where observing of `children` doesn't report changes between `oldValue` and `newValue`.
            parent.version = parent.version
        }
    }
}
