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
    struct Collection {
        #if TESTING
        static let knownDataKeys: [String] = ["name"]
        #else
        static let knownDataKeys: [String] = ["key", "version", "name", "parentCollection", "relations"]
        #endif
    }

    struct Item {
        static let title = "title"
        static let abstract = "abstractNote"
        static let note = "note"
        static let date = "date"
        static let reporter = "reporter"
        static let court = "court"
        static let publisher = "publisher"
        static let publicationTitle = "publicationTitle"
        static let doi = "DOI"
        static let url = "url"
        static let accessDate = "accessDate"
        static let extra = "extra"

        struct Attachment {
            static let linkMode = "linkMode"
            static let contentType = "contentType"
            static let md5 = "md5"
            static let mtime = "mtime"
            static let title = "title"
            static let filename = "filename"
            static let url = "url"
            static let charset = "charset"
            static let path = "path"

            static var knownKeys: Set<String> {
                return [Attachment.title, Attachment.contentType, Attachment.md5, Attachment.mtime, Attachment.filename, Attachment.linkMode, Attachment.charset, Attachment.path, Attachment.url]
            }

            static var fieldKeys: [String] {
                return [Item.title, Attachment.filename, Attachment.contentType, Attachment.linkMode, Attachment.md5, Attachment.mtime, Attachment.url, Item.accessDate]
            }
        }

        struct Annotation {
            struct Position {
                static let pageIndex = "pageIndex"
                static let rects = "rects"
                static let paths = "paths"
                static let lineWidth = "width"
            }

            static let type = "annotationType"
            static let text = "annotationText"
            static let comment = "annotationComment"
            static let color = "annotationColor"
            static let pageLabel = "annotationPageLabel"
            static let sortIndex = "annotationSortIndex"
            static let position = "annotationPosition"
            static let authorName = "annotationAuthorName"

            static var knownKeys: Set<String> {
                return [Annotation.color, Annotation.comment, Annotation.pageLabel, Annotation.position, Annotation.text, Annotation.type, Annotation.sortIndex, Annotation.authorName]
            }

            static func fields(for type: AnnotationType) -> [KeyBaseKeyPair] {
                switch type {
                case .highlight:
                    return [KeyBaseKeyPair(key: Annotation.type, baseKey: nil),
                            KeyBaseKeyPair(key: Annotation.comment, baseKey: nil),
                            KeyBaseKeyPair(key: Annotation.color, baseKey: nil),
                            KeyBaseKeyPair(key: Annotation.sortIndex, baseKey: nil),
                            KeyBaseKeyPair(key: Annotation.text, baseKey: nil)]

                case .ink:
                    return [KeyBaseKeyPair(key: Annotation.type, baseKey: nil),
                            KeyBaseKeyPair(key: Annotation.comment, baseKey: nil),
                            KeyBaseKeyPair(key: Annotation.color, baseKey: nil),
                            KeyBaseKeyPair(key: Annotation.sortIndex, baseKey: nil)]

                case .note, .image:
                    return [KeyBaseKeyPair(key: Annotation.type, baseKey: nil),
                            KeyBaseKeyPair(key: Annotation.comment, baseKey: nil),
                            KeyBaseKeyPair(key: Annotation.color, baseKey: nil),
                            KeyBaseKeyPair(key: Annotation.sortIndex, baseKey: nil)]
                }
            }
        }

        static func clean(doi: String) -> String {
            guard !doi.isEmpty else { return "" }

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

        static let knownNonFieldKeys: [String] = ["creators", "itemType", "version", "key", "tags", "deleted", "collections", "relations", "dateAdded", "dateModified", "parentItem", "inPublications"]
    }

    struct Search {
        #if TESTING
        static let knownDataKeys: [String] = ["name", "conditions"]
        #else
        static let knownDataKeys: [String] = ["key", "version", "name", "conditions"]
        #endif
    }
}
