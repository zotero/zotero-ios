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
    case loadAnnotations(UIUserInterfaceStyle)
    case searchAnnotations(String)
    case selectAnnotation(Annotation?)
    case selectAnnotationFromDocument(key: String, page: Int)
    case removeAnnotation(Annotation)
    case annotationChanged(PSPDFKit.Annotation, isDark: Bool)
    case annotationsAdded([PSPDFKit.Annotation], isDark: Bool)
    case annotationsRemoved([PSPDFKit.Annotation])
    case requestPreviews(keys: [String], notify: Bool, isDark: Bool)
    case setComment(String, String)
    case setTags([Tag], String)
    case setHighlight(String, String)
    case userInterfaceStyleChanged(UIUserInterfaceStyle)
    case updateAnnotationPreviews(userInterfaceIsDark: Bool)
    case setActiveColor(String)
    case saveChanges
    case create(annotation: AnnotationType, pageIndex: PageIndex, origin: CGPoint, interfaceStyle: UIUserInterfaceStyle)
}

#endif
