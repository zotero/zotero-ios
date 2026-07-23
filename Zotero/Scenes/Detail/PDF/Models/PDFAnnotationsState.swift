//
//  PDFAnnotationsState.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 10/03/2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKit
import RealmSwift

struct PDFAnnotationsState: ViewModelState, ReaderState {
    struct Changes: OptionSet {
        typealias RawValue = UInt16

        let rawValue: UInt16

        static let annotations = Changes(rawValue: 1 << 0)
        static let selection = Changes(rawValue: 1 << 1)
        static let activeComment = Changes(rawValue: 1 << 2)
        static let sidebarEditing = Changes(rawValue: 1 << 3)
        static let sidebarEditingSelection = Changes(rawValue: 1 << 4)
        static let filter = Changes(rawValue: 1 << 5)
        static let library = Changes(rawValue: 1 << 6)
        static let appearance = Changes(rawValue: 1 << 7)
    }

    let key: String
    let document: PSPDFKit.Document
    let userId: Int
    let username: String

    var library: Library
    var settings: PDFSettings
    var interfaceStyle: UIUserInterfaceStyle
    var sortedKeys: [PDFReaderAnnotationKey]
    var annotationPages: IndexSet
    var snapshotKeys: [PDFReaderAnnotationKey]?
    var updatedAnnotationKeys: [PDFReaderAnnotationKey]?
    var selectedAnnotationKey: PDFReaderAnnotationKey?
    var selectionFromSidebar: Bool
    var selectedAnnotationCommentActive: Bool
    var selectedAnnotationsDuringEditing: Set<PDFReaderAnnotationKey>
    var focusOnSelectionIfNeeded: Bool
    var sidebarEditingEnabled: Bool
    var deletionEnabled: Bool
    var mergingEnabled: Bool
    var searchTerm: String?
    var filter: AnnotationsFilter?
    var databaseAnnotations: Results<RItem>?
    var documentAnnotations: Results<RDocumentAnnotation>?
    let documentAnnotationKeys: [PDFReaderAnnotationKey]
    var documentAnnotationUniqueBaseColors: [String]
    var changes: Changes
    var outgoingAction: PDFAnnotationsOutputAction?

    init(
        key: String,
        document: PSPDFKit.Document,
        userId: Int,
        username: String,
        library: Library,
        settings: PDFSettings,
        interfaceStyle: UIUserInterfaceStyle,
        annotationPages: IndexSet = IndexSet(),
        selectedAnnotationKey: PDFReaderAnnotationKey? = nil,
        selectedAnnotationCommentActive: Bool = false,
        sidebarEditingEnabled: Bool = false,
        searchTerm: String? = nil,
        filter: AnnotationsFilter? = nil,
        databaseAnnotations: Results<RItem>? = nil,
        documentAnnotations: Results<RDocumentAnnotation>? = nil,
        documentAnnotationKeys: [PDFReaderAnnotationKey] = [],
        documentAnnotationUniqueBaseColors: [String] = [],
        changes: Changes = []
    ) {
        self.key = key
        self.document = document
        self.userId = userId
        self.username = username
        self.library = library
        self.settings = settings
        self.interfaceStyle = interfaceStyle
        self.annotationPages = annotationPages
        self.updatedAnnotationKeys = nil
        self.selectedAnnotationKey = selectedAnnotationKey
        self.selectionFromSidebar = false
        self.selectedAnnotationCommentActive = selectedAnnotationCommentActive
        selectedAnnotationsDuringEditing = []
        self.sidebarEditingEnabled = sidebarEditingEnabled
        deletionEnabled = false
        mergingEnabled = false
        self.searchTerm = searchTerm
        self.filter = filter
        self.databaseAnnotations = databaseAnnotations
        self.documentAnnotations = documentAnnotations
        self.documentAnnotationKeys = documentAnnotationKeys
        self.documentAnnotationUniqueBaseColors = documentAnnotationUniqueBaseColors
        self.sortedKeys = []
        self.snapshotKeys = nil
        self.changes = changes
        self.outgoingAction = nil
        focusOnSelectionIfNeeded = true
    }

    mutating func cleanup() {
        changes = []
        updatedAnnotationKeys = nil
        focusOnSelectionIfNeeded = false
        selectionFromSidebar = false
        outgoingAction = nil
    }

    var selectedReaderAnnotation: ReaderAnnotation? {
        guard let selectedAnnotationKey else { return nil }
        return annotation(for: selectedAnnotationKey)
    }

    func annotation(for key: PDFReaderAnnotationKey) -> PDFAnnotation? {
        switch key.type {
        case .database:
            return databaseAnnotations?.filter(.key(key.key)).first.flatMap({ PDFDatabaseAnnotation(item: $0) })

        case .document:
            return documentAnnotations?.filter(.key(key.key)).first.flatMap({ PDFDocumentAnnotation(annotation: $0, displayName: displayName, username: username) })
        }
    }
}
