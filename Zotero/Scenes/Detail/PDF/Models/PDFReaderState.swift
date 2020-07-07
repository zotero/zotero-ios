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

struct PDFReaderState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let annotations = Changes(rawValue: 1 << 0)
        static let selection = Changes(rawValue: 1 << 1)
    }

    private static let activeColorKey = "PDFReaderState.activeColor"

    let key: String
    let libraryId: LibraryIdentifier
    let document: Document
    let previewCache: NSCache<NSString, UIImage>
    let commentFont: UIFont

    var annotations: [Int: [Annotation]]
    var annotationsSnapshot: [Int: [Annotation]]?
    var comments: [String: NSAttributedString]
    var activeColor: UIColor
    var currentFilter: String?
    var changes: Changes
    var selectedAnnotation: Annotation?
    /// Location to focus in document
    var focusDocumentLocation: AnnotationDocumentLocation?
    /// Annotation key to focus in annotation sidebar
    var focusSidebarIndexPath: IndexPath?
    /// Annotations that need to be reloaded/inserted/removed in sidebar
    var updatedAnnotationIndexPaths: [IndexPath]?
    var insertedAnnotationIndexPaths: [IndexPath]?
    var removedAnnotationIndexPaths: [IndexPath]?
    /// Annotations that loaded their preview images and need to show them
    var loadedPreviewImageAnnotationKeys: Set<String>?

    init(url: URL, key: String, libraryId: LibraryIdentifier) {
        self.key = key
        self.libraryId = libraryId
        self.previewCache = NSCache()
        self.document = Document(url: url)
        self.annotations = [:]
        self.comments = [:]
        self.commentFont = UIFont.preferredFont(forTextStyle: .body)
        self.activeColor = UserDefaults.standard.string(forKey: PDFReaderState.activeColorKey)
                                                .flatMap({ UIColor(hex: $0) }) ?? AnnotationsConfig.defaultActiveColor
        self.changes = []

        self.previewCache.totalCostLimit = 1024 * 1024 * 10 // Cache object limit - 10 MB
    }

    mutating func cleanup() {
        self.changes = []
        self.focusDocumentLocation = nil
        self.focusSidebarIndexPath = nil
        self.updatedAnnotationIndexPaths = nil
        self.insertedAnnotationIndexPaths = nil
        self.removedAnnotationIndexPaths = nil
        self.loadedPreviewImageAnnotationKeys = nil
    }
}

#endif
