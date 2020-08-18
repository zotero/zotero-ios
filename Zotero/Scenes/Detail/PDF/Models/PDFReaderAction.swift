//
//  PDFReaderAction.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import Foundation

import PSPDFKit

enum PDFReaderAction {
    case startObservingAnnotationChanges
    case loadAnnotations
    case searchAnnotations(String)
    case selectAnnotation(Annotation?)
    case selectAnnotationFromDocument(key: String, page: Int)
    case removeAnnotation(Annotation)
    case annotationChanged(PSPDFKit.Annotation, isDark: Bool)
    case annotationsAdded([PSPDFKit.Annotation], isDark: Bool)
    case annotationsRemoved([PSPDFKit.Annotation])
    case requestPreviews(keys: [String], notify: Bool, isDark: Bool)
    case setComment(String, IndexPath)
    case setTags([Tag], IndexPath)
    case setHighlight(String, IndexPath)
    case userInterfaceStyleChanged
    case updateAnnotationPreviews(userInterfaceIsDark: Bool)
    case setActiveColor(String)
    case saveChanges
}

#endif
