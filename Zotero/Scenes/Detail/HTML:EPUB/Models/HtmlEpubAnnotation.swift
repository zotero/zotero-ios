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
}
