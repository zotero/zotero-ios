//
//  PDFReaderAction.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

import PSPDFKit
import PSPDFKitUI
import RealmSwift

enum PDFReaderAction {
    case startObservingAnnotationPreviewChanges
    case loadDocumentData(boundingBoxConverter: AnnotationBoundingBoxConverter)
    case searchAnnotations(String)
    case selectAnnotation(PDFReaderState.AnnotationKey)
    case selectAnnotationFromDocument(PDFReaderState.AnnotationKey)
    case deselectSelectedAnnotation
    case selectAnnotationDuringEditing(PDFReaderState.AnnotationKey)
    case deselectAnnotationDuringEditing(PDFReaderState.AnnotationKey)
    case removeAnnotation(PDFReaderState.AnnotationKey)
    case removeSelectedAnnotations
    case mergeSelectedAnnotations
    case requestPreviews(keys: [String], notify: Bool)
    case setTags(key: String, tags: [Tag])
    case setColor(key: String, color: String)
    case setLineWidth(key: String, width: CGFloat)
    case setHighlight(key: String, text: String)
    case updateAnnotationProperties(key: String, color: String, lineWidth: CGFloat, pageLabel: String, updateSubsequentLabels: Bool, highlightText: String)
    case userInterfaceStyleChanged(UIUserInterfaceStyle)
    case updateAnnotationPreviews
    case setActiveColor(String)
    case setActiveLineWidth(CGFloat)
    case setActiveEraserSize(CGFloat)
    case create(annotation: AnnotationType, pageIndex: PageIndex, origin: CGPoint)
    case parseAndCacheComment(key: String, comment: String)
    case setComment(key: String, comment: NSAttributedString)
    case setCommentActive(Bool)
    case setVisiblePage(Int)
    case export(PDFExportSettings)
    case clearTmpAnnotationPreviews
    case setSidebarEditingEnabled(Bool)
    case setSettings(settings: PDFSettings, currentUserInterfaceStyle: UIUserInterfaceStyle)
    case changeIdleTimerDisabled(Bool)
    case changeFilter(AnnotationsFilter?)
    case submitPendingPage(Int)
}

#endif
