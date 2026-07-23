//
//  PDFReaderAction.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKit
import PSPDFKitUI
import RealmSwift

enum PDFReaderAction {
    case prepareDocumentProvider
    case loadDocumentData
    case selectAnnotation(PDFReaderAnnotationKey)
    case selectAnnotationFromDocument(PDFReaderAnnotationKey)
    case deselectSelectedAnnotation
    case deselectSelectedAnnotationFromDocument
    case removeAnnotation(PDFReaderAnnotationKey)
    case mergeAnnotations(Set<PDFReaderAnnotationKey>)
    case removeAnnotations(Set<PDFReaderAnnotationKey>)
    case setTags(key: String, tags: [Tag])
    case setColor(key: String, color: String)
    case setLineWidth(key: String, width: CGFloat)
    case updateAnnotationProperties(
        key: String,
        type: AnnotationType,
        color: String,
        lineWidth: CGFloat,
        fontSize: CGFloat,
        pageLabel: String,
        updateSubsequentLabels: Bool,
        highlightText: NSAttributedString,
        higlightFont: UIFont
    )
    case userInterfaceStyleChanged(UIUserInterfaceStyle)
    case setToolOptions(color: String?, size: CGFloat?, tool: PSPDFKit.Annotation.Tool)
    case createNote(pageIndex: PageIndex, origin: CGPoint)
    case createImage(pageIndex: PageIndex, origin: CGPoint)
    case createHighlight(pageIndex: PageIndex, rects: [CGRect])
    case createUnderline(pageIndex: PageIndex, rects: [CGRect])
    case parseAndCacheText(key: String, text: String, font: UIFont)
    case parseAndCacheComment(key: String, comment: String)
    case setComment(key: String, comment: NSAttributedString)
    case setCommentActive(Bool)
    case setVisiblePage(page: Int, userActionFromDocument: Bool, fromThumbnailList: Bool)
    case setFontSize(key: String, size: CGFloat)
    case export(includeAnnotations: Bool)
    case clearTmpData
    case setSidebarEditingEnabled(Bool)
    case setSettings(settings: PDFSettings)
    case changeIdleTimerDisabled(Bool)
    case filterAnnotations(searchTerm: String?, filter: AnnotationsFilter?)
    case submitPendingPage(Int)
    case deinitialiseReader
    case unlock(String)
}
