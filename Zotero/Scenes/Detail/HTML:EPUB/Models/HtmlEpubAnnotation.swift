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
    let dateModified: Date
    let dateCreated: Date
    let tags: [Tag]

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
            dateModified: dateModified,
            dateCreated: dateCreated,
            tags: tags
        )
    }

    func editability(currentUserId: Int, library: Library) -> AnnotationEditability {
        switch library.identifier {
        case .custom:
            return library.metadataEditable ? .editable : .notEditable

        case .group:
            if !library.metadataEditable {
                return .notEditable
            }
            return self.isAuthor ? .editable : .deletable
        }
    }
}
