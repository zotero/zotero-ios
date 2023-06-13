//
//  AttachmentUpload.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct AttachmentUpload: Equatable {
    let libraryId: LibraryIdentifier
    let key: String
    let filename: String
    let contentType: String
    let md5: String
    let mtime: Int
    let file: File
    let oldMd5: String?

    static func == (lhs: AttachmentUpload, rhs: AttachmentUpload) -> Bool {
        return lhs.libraryId == rhs.libraryId && lhs.key == rhs.key && lhs.filename == rhs.filename && lhs.contentType == rhs.contentType &&
               lhs.md5 == rhs.md5 && lhs.mtime == rhs.mtime
    }
}
