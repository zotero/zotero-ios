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

typealias AnnotationDocumentLocation = (page: Int, boundingBox: CGRect)
typealias AnnotationSidebarLocation = (index: Int, page: Int)

struct PDFReaderState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let annotations = Changes(rawValue: 1 << 0)
        static let selection = Changes(rawValue: 1 << 1)
    }

    let key: String
    let document: Document
    let previewCache: NSCache<NSString, UIImage>

    var annotations: [Int: [Annotation]]
    var annotationsSnapshot: [Int: [Annotation]]?
    var changes: Changes
    var selectedAnnotation: Annotation?
    /// Location to focus in document
    var focusDocumentLocation: AnnotationDocumentLocation?
    /// Annotation key to focus in annotation sidebar
    var focusSidebarLocation: AnnotationSidebarLocation?
    /// Annotations that need to be reloaded in sidebar
    var updatedAnnotationIndexPaths: [IndexPath]?

    init(url: URL, key: String) {
        self.key = key
        self.previewCache = NSCache()
        self.document = Document(url: url)
        self.annotations = [:]
        self.changes = []

        self.previewCache.totalCostLimit = 1024 * 1024 * 10 // Cache object limit - 10 MB
    }

    mutating func cleanup() {
        self.changes = []
        self.focusDocumentLocation = nil
        self.focusSidebarLocation = nil
        self.updatedAnnotationIndexPaths = nil
    }
}

#endif
