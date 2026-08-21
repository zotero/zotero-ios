//
//  HtmlEpubReaderAction.swift
//  Zotero
//
//  Created by Michal Rentka on 14.09.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

enum HtmlEpubReaderAction {
    case changeFilter(AnnotationsFilter?)
    case changeIdleTimerDisabled(Bool)
    case createAnnotationFromSelection(AnnotationType)
    case deinitialiseReader
    case deselectAnnotationDuringEditing(String)
    case deselectSelectedAnnotation
    /// Ends a read aloud highlight session. `annotation` is the annotation reported by the reader, which is stored in the database, `nil` when the session was discarded. `key` is the key of
    /// the session annotation, if the reader already assigned one, whose saves are ignored from now on.
    case endReadAloudAnnotationSession(annotation: [String: Any]?, key: String?)
    case initialiseReader
    case loadDocument
    case parseAndCacheComment(key: String, comment: String)
    case parseAndCacheText(key: String, text: String, font: UIFont)
    case parseOutline(data: [String: Any])
    case processDocumentSearchResults(data: [String: Any])
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
    case setCurrentOutline(id: UUID)
    case setSelectedTextParams([String: Any])
    case setSettings(HtmlEpubSettings)
    case setSidebarEditingEnabled(Bool)
    case setTags(key: String, tags: [Tag])
    case setToolOptions(color: String?, size: CGFloat?, tool: AnnotationTool)
    case setViewState([String: Any])
    case setViewStats([String: Any])
    case showAnnotationPopover(key: String, rect: CGRect)
    /// Starts a read aloud highlight session. Saves of the annotation created by the reader for the session are ignored until the session ends.
    case startReadAloudAnnotationSession
    case toggleTool(AnnotationTool)
    case updateAnnotationProperties(key: String, type: AnnotationType, color: String, lineWidth: CGFloat, pageLabel: String, updateSubsequentLabels: Bool, highlightText: NSAttributedString)
    case userInterfaceStyleChanged(UIUserInterfaceStyle)
}
