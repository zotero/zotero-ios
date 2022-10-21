//
//  MarkAttachmentsNotUploadedDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 26.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MarkAttachmentsNotUploadedDbRequest: DbRequest {
    let keys: [String]
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let attachments = database.objects(RItem.self).filter(.keys(self.keys, in: self.libraryId))
        for attachment in attachments {
            guard !attachment.isInvalidated else { continue }
            attachment.attachmentNeedsSync = true
            attachment.changeType = .syncResponse
        }
    }
}
