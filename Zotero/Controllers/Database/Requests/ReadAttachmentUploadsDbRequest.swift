//
//  ReadAttachmentUploadsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 19/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift
import CocoaLumberjackSwift

struct ReadAttachmentUploadsDbRequest: DbResponseRequest {
    typealias Response = [AttachmentUpload]

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> [AttachmentUpload] {
        let items = database.objects(RItem.self).filter(.itemsNotChangedAndNeedUpload(in: self.libraryId))
        let uploads = items.compactMap({ item -> AttachmentUpload? in
            guard let linkMode = item.fields.filter(.key(FieldKeys.Item.Attachment.linkMode)).first.flatMap({ LinkMode(rawValue: $0.value) }),
                  let contentType = item.fields.filter(.key(FieldKeys.Item.Attachment.contentType)).first?.value else { return nil }

            let mtime = item.fields.filter(.key(FieldKeys.Item.Attachment.mtime)).first.flatMap({ Int($0.value) }) ?? 0
            let md5 = item.fields.filter(.key(FieldKeys.Item.Attachment.md5)).first?.value ?? ""
            let filename = item.fields.filter("key = %@", FieldKeys.Item.Attachment.filename).first?.value ?? ""
            let file: File

            switch linkMode {
            case .embeddedImage:
                if let parent = item.parent {
                    switch parent.rawType {
                    case ItemTypes.annotation:
                        if let attachment = parent.parent {
                            file = Files.annotationPreview(annotationKey: parent.key, pdfKey: attachment.key, isDark: false)
                        } else {
                            // This shouldn't really happen, annotation must always have a pdf parent! But let's not crash and return default attachment file.
                            file = Files.attachmentFile(in: self.libraryId, key: item.key, contentType: contentType)
                            DDLogError("ReadAttachmentUploadsDbRequest: uploading file for embedded image of annotation without parent (\(parent.key), \(item.key))!")
                        }
                    default:
                        // Embedded image can only be assigned to annotations currently, but return default file just in case.
                        file = Files.attachmentFile(in: self.libraryId, key: item.key, contentType: contentType)
                        DDLogError("ReadAttachmentUploadsDbRequest: uploading file for embedded image with parent of unknown type ('\(parent.rawType)', \(item.key))!")
                    }
                } else {
                    // This shouldn't really happen, embedded image must always have a parent! But let's not crash and return default attachment file.
                    file = Files.attachmentFile(in: self.libraryId, key: item.key, contentType: contentType)
                    DDLogError("ReadAttachmentUploadsDbRequest: uploading file for embedded image without parent (\(item.key))!")
                }
            default:
                file = Files.attachmentFile(in: self.libraryId, key: item.key, contentType: contentType)
            }

            return AttachmentUpload(libraryId: self.libraryId, key: item.key,
                                    filename: filename, contentType: contentType,
                                    md5: md5, mtime: mtime, file: file)
        })
        return Array(uploads)
    }
}
