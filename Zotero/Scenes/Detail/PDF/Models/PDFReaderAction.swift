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
    case annotationChanged(PSPDFKit.Annotation)
    case annotationsAdded([PSPDFKit.Annotation])
    case annotationsRemoved([PSPDFKit.Annotation])
    case requestPreviews(keys: [String], notify: Bool)
    case editComment(IndexPath)
    case editTags(IndexPath)
    case setComment(String, IndexPath)
    case setTags([Tag], IndexPath)
}

#endif
