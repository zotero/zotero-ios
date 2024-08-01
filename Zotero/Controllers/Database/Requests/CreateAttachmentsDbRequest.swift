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

    func process(in database: Realm) throws -> [(String, String)] {
        guard let libraryId = attachments.first?.libraryId else { return [] }

        let parent = parentKey.flatMap({ database.objects(RItem.self).uniqueObject(key: $0, libraryId: libraryId) })
        if let parent = parent {
            // This is to mitigate the issue in item detail screen (ItemDetailActionHandler.shouldReloadData) where observing of `children` doesn't report changes between `oldValue` and `newValue`.
            parent.version = parent.version
        }

        var failed: [(String, String)] = []

        for attachment in attachments {
            do {
                let attachment = try CreateAttachmentDbRequest(
                    attachment: attachment,
                    parentKey: nil,
                    localizedType: localizedType,
                    includeAccessDate: attachment.hasUrl,
                    collections: collections,
                    tags: []
                ).process(in: database)
                if let parent = parent {
                    attachment.parent = parent
                    attachment.changes.append(RObjectChange.create(changes: RItemChanges.parent))
                }
            } catch let error {
                DDLogError("CreateAttachmentsDbRequest: could not create attachment - \(error)")
                failed.append((attachment.key, attachment.title))
            }
        }

        return failed
    }
}
