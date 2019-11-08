//
//  FieldKeys.swift
//  Zotero
//
//  Created by Michal Rentka on 15/04/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct FieldKeys {
    static let title = "title"
    static let abstract = "abstractNote"
    static let note = "note"
    static let date = "date"
    static let reporter = "reporter"
    static let court = "court"
    static let publisher = "publisher"
    static let publicationTitle = "publicationTitle"
    // Attachment attributes
    static let linkMode = "linkMode"
    static let contentType = "contentType"
    static let md5 = "md5"
    static let mtime = "mtime"
    static let filename = "filename"
    static let url = "url"

    static var attachmentFieldKeys: [String] {
        return [FieldKeys.title, FieldKeys.filename,
                FieldKeys.contentType, FieldKeys.linkMode,
                FieldKeys.md5, FieldKeys.mtime,
                FieldKeys.url]
    }
}
