//
//  HtmlEpubReaderAction.swift
//  Zotero
//
//  Created by Michal Rentka on 14.09.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum HtmlEpubReaderAction {
    case deselectSelectedAnnotation
    case loadDocument
    case parseAndCacheComment(key: String, comment: String)
    case saveAnnotations([String: Any])
    case selectAnnotation(String)
    case selectAnnotationFromDocument([String: Any])
    case setComment(key: String, comment: NSAttributedString)
    case setCommentActive(Bool)
    case setTags(key: String, tags: [Tag])
    case toggleTool(AnnotationTool)
}
