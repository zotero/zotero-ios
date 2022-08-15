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
    unowned let fileStorage: FileStorage

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> [AttachmentUpload] {
        let items = database.objects(RItem.self).filter(.itemsNotChangedAndNeedUpload(in: self.libraryId))
        let uploads = items.compactMap({ item -> AttachmentUpload? in
            guard let contentType = item.fields.filter(.key(FieldKeys.Item.Attachment.contentType)).first?.value else {
                DDLogError("ReadAttachmentUploadsDbRequest: contentType field missing !!!")
                return nil
            }
            guard let mtimeField = item.fields.filter(.key(FieldKeys.Item.Attachment.mtime)).first else {
                DDLogError("ReadAttachmentUploadsDbRequest: mtime field missing !!!")
                return nil
            }
            guard let mtime = Int(mtimeField.value) else {
                DDLogError("ReadAttachmentUploadsDbRequest: mtime field value not a number (\"\(mtimeField.value)\") !!!")
                return nil
            }
            guard let md5Field = item.fields.filter(.key(FieldKeys.Item.Attachment.md5)).first else {
                DDLogError("ReadAttachmentUploadsDbRequest: md5 field missing !!!")
                return nil
            }
            // Always upload light version of attachment (applies to embedded_image)
            guard let attachmentType = AttachmentCreator.attachmentType(for: item, options: .light, fileStorage: nil, urlDetector: nil) else { return nil }

            let filename: String
            let file: File

            switch attachmentType {
            case .url:
                return nil
            case .file(let _filename, let contentType, _, let linkType):
                // Don't try to upload linked attachments
                guard linkType != .linkedFile else { return nil }
                file = Files.attachmentFile(in: self.libraryId, key: item.key, filename: _filename, contentType: contentType)
                filename = _filename
            }

            if md5Field.value == "<null>" {
                if let newMd5 = md5(from: file.createUrl()) {
                    md5Field.value = newMd5
                } else {
                    let fileExists = self.fileStorage.has(file)
                    DDLogError("ReadAttachmentUploadsDbRequest: original md5 field was \"<null>\", new md5 can't be calculated. File exists: \(fileExists)")
                    return nil
                }
            }

            var backendMd5: String? = item.backendMd5.isEmpty ? nil : item.backendMd5
            if backendMd5 == "<null>" {
                // Don't need to update item here, it'll get updated in `MarkAttachmentUploadedDbRequest`.
                backendMd5 = nil
            }

            return AttachmentUpload(libraryId: self.libraryId, key: item.key, filename: filename, contentType: contentType, md5: md5Field.value, mtime: mtime, file: file, oldMd5: backendMd5)
        })
        return Array(uploads)
    }
}
