//
//  HtmlEpubAnnotation.swift
//  Zotero
//
//  Created by Michal Rentka on 28.09.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct HtmlEpubAnnotation {
    let key: String
    let type: AnnotationType
    let pageLabel: String
    let position: [String: Any]
    let author: String
    let isAuthor: Bool
    let color: String
    let comment: String
    let text: String?
    let sortIndex: String
    let dateAdded: Date
    let dateModified: Date
    let tags: [Tag]
    /// `true` if the reader saved the annotation because only its text or comment changed. Its position may be out of date then, so it's not stored.
    var onlyTextOrComment: Bool = false

    func copy(comment: String) -> HtmlEpubAnnotation {
        return HtmlEpubAnnotation(
            key: key,
            type: type,
            pageLabel: pageLabel,
            position: position,
            author: author,
            isAuthor: isAuthor,
            color: color,
            comment: comment,
            text: text,
            sortIndex: sortIndex,
            dateAdded: dateAdded,
            dateModified: dateModified,
            tags: tags,
            onlyTextOrComment: onlyTextOrComment
        )
    }
}

extension HtmlEpubAnnotation: ReaderAnnotation {
    var lineWidth: CGFloat? {
        return 0
    }

    var fontSize: CGFloat? {
        return 12
    }

    func author(displayName: String, username: String) -> String {
        return author
    }

    func isAuthor(currentUserId: Int) -> Bool {
        return isAuthor
    }

    func editability(currentUserId: Int, library: Library) -> AnnotationEditability {
        switch library.identifier {
        case .custom:
            return library.metadataEditable ? .editable : .notEditable

        case .group:
            if !library.metadataEditable {
                return .notEditable
            }
            return isAuthor ? .editable : .deletable
        }
    }
}
