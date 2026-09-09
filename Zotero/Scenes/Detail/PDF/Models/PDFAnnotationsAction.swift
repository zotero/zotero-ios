//
//  PDFAnnotationsAction.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 10/03/2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RealmSwift

enum PDFAnnotationsAction {
    case initializeSortedKeys
    case setAnnotations(
        annotationPages: IndexSet,
        changedAnnotationKeys: [PDFReaderAnnotationKey]?,
        selectedAnnotationKey: PDFReaderAnnotationKey?,
        selectionFromDocument: Bool,
        databaseAnnotations: Results<RItem>?
    )
    case setSelection(
        selectedAnnotationKey: PDFReaderAnnotationKey?,
        selectionFromDocument: Bool
    )
    case setCommentActive(Bool)
    case setSidebarEditingEnabled(Bool)
    case setSidebarEditingSelection(deletionEnabled: Bool, mergingEnabled: Bool)
    case selectAnnotationDuringEditing(PDFReaderAnnotationKey)
    case deselectAnnotationDuringEditing(PDFReaderAnnotationKey)
    case mergeSelectedAnnotations
    case removeSelectedAnnotations
    case setSearchTerm(String)
    case setFilter(AnnotationsFilter?)
    case setLibrary(Library)
    case setAppearance(settings: PDFSettings, interfaceStyle: UIUserInterfaceStyle)
    case setSettings(PDFSettings)
    case send(PDFAnnotationsOutputAction)
}

enum PDFAnnotationsOutputAction {
    case setTags(key: String, tags: [Tag])
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
    case removeAnnotation(PDFReaderAnnotationKey)
    case setComment(key: String, comment: NSAttributedString)
    case mergeAnnotations(Set<PDFReaderAnnotationKey>)
    case removeAnnotations(Set<PDFReaderAnnotationKey>)
}
