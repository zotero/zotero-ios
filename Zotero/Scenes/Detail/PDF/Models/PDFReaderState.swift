//
//  PDFReaderState.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import UIKit

import PSPDFKit

typealias AnnotationLocation = (page: Int, boundingBox: CGRect)

struct PDFReaderState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let annotations = Changes(rawValue: 1 << 0)
    }

    static let supportedAnnotations: PSPDFKit.Annotation.Kind = [.note, .highlight, .square]
    static let zoteroAnnotationKey = "isZoteroAnnotation"
    static let zoteroHighlightKey = "isZoteroHighlight"
    static let zoteroKeyKey = "zoteroKey"

    let document: Document

    var annotations: [Int: [Annotation]]
    var annotationsSnapshot: [Int: [Annotation]]?
    var changes: Changes
    var selectedAnnotation: Annotation?
    var highlightSelectionAnnotation: SquareAnnotation?
    var focusLocation: AnnotationLocation?

    init(url: URL) {
        self.document = Document(url: url)
        self.annotations = [:]
        self.changes = []
    }

    mutating func cleanup() {
        self.changes = []
        self.focusLocation = nil
    }
}

#endif
