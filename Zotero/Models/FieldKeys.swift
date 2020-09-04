//
//  FieldKeys.swift
//  Zotero
//
//  Created by Michal Rentka on 15/04/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct FieldKeys {
    static let title = "title"
    static let abstract = "abstractNote"
    static let note = "note"
    static let date = "date"
    static let reporter = "reporter"
    static let court = "court"
    static let publisher = "publisher"
    static let publicationTitle = "publicationTitle"
    static let doi = "DOI"
    static let accessDate = "accessDate"
    // Attachment attributes
    static let linkMode = "linkMode"
    static let contentType = "contentType"
    static let md5 = "md5"
    static let mtime = "mtime"
    static let filename = "filename"
    static let url = "url"
    static let charset = "charset"

    static var attachmentFieldKeys: [String] {
        return [FieldKeys.title, FieldKeys.filename,
                FieldKeys.contentType, FieldKeys.linkMode,
                FieldKeys.md5, FieldKeys.mtime,
                FieldKeys.url]
    }

    static func clean(doi: String) -> String {
        do {
            let regex = try NSRegularExpression(pattern: #"10(?:\.[0-9]{4,})?\/[^\s]*[^\s\.,]"#)
            if let match = regex.firstMatch(in: doi, range: NSRange(doi.startIndex..., in: doi)),
               let range = Range(match.range, in: doi) {
                return String(doi[range])
            }
            return ""
        } catch let error {
            DDLogError("FieldKeys: can't clean DOI - \(error)")
            return ""
        }
    }

    static func isDoi(_ value: String) -> Bool {
        return !clean(doi: value).isEmpty
    }
}
