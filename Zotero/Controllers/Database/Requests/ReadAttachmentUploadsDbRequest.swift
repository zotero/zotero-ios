//
//  ReadAttachmentUploadsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 19/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct ReadAttachmentUploadsDbRequest: DbResponseRequest {
    typealias Response = [AttachmentUpload]

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> [AttachmentUpload] {
        let items = database.objects(RItem.self).filter(.itemsNotChangedAndNeedUpload(in: self.libraryId))
        let uploads = items.compactMap({ item -> AttachmentUpload? in
            guard let contentType = item.fields.filter(.key(FieldKeys.Item.Attachment.contentType)).first?.value,
                  // Always upload light version of attachment (applies to embedded_image)
                  let attachmentType = AttachmentCreator.attachmentType(for: item, options: .light, fileStorage: nil, urlDetector: nil) else { return nil }

            let filename: String
            let file: File

            switch attachmentType {
            case .url:
                return nil
            case .file(let _filename, let contentType, let location, let linkType):
                // Don't try to upload linked attachments
                guard linkType != .linkedFile && location == .local else { return nil }
                file = Files.newAttachmentFile(in: self.libraryId, key: item.key, filename: _filename, contentType: contentType)
                filename = _filename
            }

            let mtime = item.fields.filter(.key(FieldKeys.Item.Attachment.mtime)).first.flatMap({ Int($0.value) }) ?? 0
            let md5 = item.fields.filter(.key(FieldKeys.Item.Attachment.md5)).first?.value ?? ""

            return AttachmentUpload(libraryId: self.libraryId, key: item.key, filename: filename, contentType: contentType, md5: md5, mtime: mtime, file: file,
                                    oldMd5: (item.backendMd5.isEmpty ? nil : item.backendMd5))
        })
        return Array(uploads)
    }
}
