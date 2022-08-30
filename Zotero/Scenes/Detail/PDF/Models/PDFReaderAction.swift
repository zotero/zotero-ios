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
    case removeAnnotation(String)
    case removeSelectedAnnotations
    case mergeSelectedAnnotations
    case annotationsAdded(annotations: [PSPDFKit.Annotation], selectFirst: Bool)
    case requestPreviews(keys: [String], notify: Bool)
    case setComment(key: String, comment: NSAttributedString)
    case setTags(key: String, tags: [Tag])
    case setColor(key: String, color: String)
    case setLineWidth(key: String, width: CGFloat)
    case setHighlight(key: String, text: String)
    case updateAnnotationProperties(Annotation)
    case userInterfaceStyleChanged(UIUserInterfaceStyle)
    case updateAnnotationPreviews
    case setActiveColor(String)
    case setActiveLineWidth(CGFloat)
    case setActiveEraserSize(CGFloat)
    case create(annotation: AnnotationType, pageIndex: PageIndex, origin: CGPoint)
    case setCommentActive(Bool)
    case setVisiblePage(Int)
    case export
    case clearTmpAnnotationPreviews
    case setSidebarEditingEnabled(Bool)
    case setSettings(PDFSettings)
    case changeIdleTimerDisabled(Bool)
    case changeFilter(AnnotationsFilter?)
}

#endif
