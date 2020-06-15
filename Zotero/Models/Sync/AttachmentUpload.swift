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

    var file: File {
        return Files.attachmentFile(in: self.libraryId, key: self.key, contentType: self.contentType)
    }
}
