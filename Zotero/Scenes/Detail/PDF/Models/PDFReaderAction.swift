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
    case startObservingAnnotationChanges
    case loadDocumentData
    case searchAnnotations(String)
    case selectAnnotation(String)
    case selectAnnotationFromDocument(String)
    case deselectSelectedAnnotation
    case selectAnnotationDuringEditing(String)
    case deselectAnnotationDuringEditing(String)
    case removeAnnotation(AnnotationPosition)
    case removeSelectedAnnotations
    case mergeSelectedAnnotations
    case annotationsAdded(annotations: [PSPDFKit.Annotation], selectFirst: Bool)
    case annotationsRemoved([PSPDFKit.Annotation])
    case annotationChanged(PSPDFKit.Annotation)
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
    case saveChanges
    case create(annotation: AnnotationType, pageIndex: PageIndex, origin: CGPoint)
    case setCommentActive(Bool)
    case setVisiblePage(Int)
    case export
    case clearTmpAnnotationPreviews
    case itemsChange(objects: Results<RItem>, deletions: [Int], insertions: [Int], modifications: [Int])
    case updateDbPositions(objects: Results<RItem>, deletions: [Int], insertions: [Int])
    case notificationReceived(Notification.Name)
    case annotationChangeNotificationReceived(String)
    case setSidebarEditingEnabled(Bool)
    case setSettings(PDFSettings)
    case changeIdleTimerDisabled(Bool)
    case changeFilter(AnnotationsFilter?)
}

#endif
