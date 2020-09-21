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
            guard let contentType = item.fields.filter(.key(FieldKeys.Item.Attachment.contentType)).first?.value,
                  let file = AttachmentCreator.file(for: item) else { return nil }

            let mtime = item.fields.filter(.key(FieldKeys.Item.Attachment.mtime)).first.flatMap({ Int($0.value) }) ?? 0
            let md5 = item.fields.filter(.key(FieldKeys.Item.Attachment.md5)).first?.value ?? ""
            let filename = item.fields.filter(.key(FieldKeys.Item.Attachment.filename)).first?.value ?? file.name

            return AttachmentUpload(libraryId: self.libraryId, key: item.key,
                                    filename: filename, contentType: contentType,
                                    md5: md5, mtime: mtime, file: file)
        })
        return Array(uploads)
    }
}
