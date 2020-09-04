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
    typealias Response = [AttachmentUpload]

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> [AttachmentUpload] {
        let items = database.objects(RItem.self).filter(.itemsNotChangedAndNeedUpload(in: self.libraryId))
        let uploads = items.compactMap({ item -> AttachmentUpload? in
            guard let contentType = item.fields.filter("key = %@", ItemFieldKeys.contentType).first?.value,
                  let md5 = item.fields.filter("key = %@", ItemFieldKeys.md5).first?.value,
                  let mtime = (item.fields.filter("key = %@", ItemFieldKeys.mtime).first?.value).flatMap(Int.init) else { return nil }
            let filename = item.fields.filter("key = %@", ItemFieldKeys.filename).first?.value ?? ""
            return AttachmentUpload(libraryId: self.libraryId, key: item.key,
                                    filename: filename, contentType: contentType,
                                    md5: md5, mtime: mtime)
        })
        return Array(uploads)
    }
}
