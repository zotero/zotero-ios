//
//  HtmlEpubReaderAction.swift
//  Zotero
//
//  Created by Michal Rentka on 14.09.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum HtmlEpubReaderAction {
    case loadDocument
    case saveAnnotations([String: Any])
    case selectAnnotations([String: Any])
    case toggleTool(AnnotationTool)
}
