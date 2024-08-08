//
//  HtmlEpubReaderAction.swift
//  Zotero
//
//  Created by Michal Rentka on 14.09.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum HtmlEpubReaderAction {
    case changeFilter(AnnotationsFilter?)
    case changeIdleTimerDisabled(Bool)
    case deinitialiseReader
    case deselectAnnotationDuringEditing(String)
    case deselectSelectedAnnotation
    case hideAnnotationPopover
    case initialiseReader
    case loadDocument
    case parseAndCacheComment(key: String, comment: String)
    case removeAnnotation(String)
    case removeSelectedAnnotations
    case saveAnnotations([String: Any])
    case searchAnnotations(String)
    case searchDocument(String)
    case selectAnnotationDuringEditing(key: String)
    case selectAnnotationFromSidebar(key: String)
    case selectAnnotationFromDocument(key: String)
    case setColor(key: String, color: String)
    case setComment(key: String, comment: NSAttributedString)
    case setCommentActive(Bool)
    case setSettings(HtmlEpubSettings)
    case setSidebarEditingEnabled(Bool)
    case setTags(key: String, tags: [Tag])
    case setToolOptions(color: String?, size: CGFloat?, tool: AnnotationTool)
    case setViewState([String: Any])
    case showAnnotationPopover(key: String, rect: CGRect)
    case toggleTool(AnnotationTool)
    case updateAnnotationProperties(key: String, color: String, lineWidth: CGFloat, pageLabel: String, updateSubsequentLabels: Bool, highlightText: String)
}
