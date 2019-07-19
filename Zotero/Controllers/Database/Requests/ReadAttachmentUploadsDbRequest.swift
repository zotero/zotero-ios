//
//  ReadAttachmentUploadsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 19/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadAttachmentUploadsDbRequest: DbResponseRequest {
    typealias Response = [SyncController.AttachmentUpload]

    let library: SyncController.Library

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> [SyncController.AttachmentUpload] {
        let items = database.objects(RItem.self).filter(Predicates.itemsNotChangedAndNeedUpload(in: self.library.libraryId))
        let uploads = items.compactMap({ item -> SyncController.AttachmentUpload? in
            guard let contentType = item.fields.filter("key = %@", FieldKeys.contentType).first?.value,
                  let ext = contentType.mimeTypeExtension else { return nil }
            let filename = item.fields.filter("key = %@", FieldKeys.filename).first?.value ?? ""
            let md5 = item.fields.filter("key = %@", FieldKeys.md5).first?.value
            let mtime = (item.fields.filter("key = %@", FieldKeys.mtime).first?.value).flatMap(Int.init)
            return SyncController.AttachmentUpload(library: self.library, key: item.key,
                                                   filename: filename, extension: ext,
                                                   md5: md5, mtime: mtime)
        })
        return Array(uploads)
    }
}
