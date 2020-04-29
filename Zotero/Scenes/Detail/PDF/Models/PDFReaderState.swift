//
//  PDFReaderState.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

#if PDFENABLED

import Foundation

import PSPDFKit

struct PDFReaderState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8
    }

    static let supportedAnnotations: PSPDFKit.Annotation.Kind = [.note, .highlight, .square]
    static let zoteroAnnotationKey = "isZoteroAnnotation"

    let document: Document

    var annotations: [Int: [Annotation]]
    var changes: Changes

    init(url: URL) {
        self.document = Document(url: url)
        self.annotations = [:]
        self.changes = []
    }

    mutating func cleanup() {
        self.changes = []
    }
}

#endif
