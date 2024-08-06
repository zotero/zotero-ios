//
//  HtmlEpubReaderState.swift
//  Zotero
//
//  Created by Michal Rentka on 14.09.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RealmSwift

struct HtmlEpubReaderState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt16

        let rawValue: UInt16

        static let activeTool = Changes(rawValue: 1 << 0)
        static let annotations = Changes(rawValue: 1 << 1)
        static let selection = Changes(rawValue: 1 << 2)
        static let activeComment = Changes(rawValue: 1 << 3)
        static let sidebarEditing = Changes(rawValue: 1 << 4)
        static let filter = Changes(rawValue: 1 << 5)
        static let toolColor = Changes(rawValue: 1 << 6)
        static let sidebarEditingSelection = Changes(rawValue: 1 << 7)
        static let settings = Changes(rawValue: 1 << 8)
        static let readerInitialised = Changes(rawValue: 1 << 9)
    }

    struct DocumentData {
        enum Page {
            case html(scrollYPercent: Double)
            case epub(cfi: String)
        }

        let type: String
        let url: URL
        let annotationsJson: String
        let page: Page?
    }

    struct DocumentUpdate {
        let deletions: [String]
        let insertions: [[String: Any]]
        let modifications: [[String: Any]]
    }

    enum Error: Swift.Error {
        case cantDeleteAnnotation
        case cantAddAnnotations
        case cantUpdateAnnotation
        case incompatibleDocument
        case unknown
    }

    let originalFile: File
    let readerFile: File
    let documentFile: File
    let key: String
    let library: Library
    let userId: Int
    let username: String
    let commentFont: UIFont

    var documentData: DocumentData?
    var settings: HtmlEpubSettings
    var activeTool: AnnotationTool?
    var toolColors: [AnnotationTool: UIColor]
    var sortedKeys: [String]
    var snapshotKeys: [String]?
    var annotations: [String: HtmlEpubAnnotation]
    var annotationSearchTerm: String?
    var annotationFilter: AnnotationsFilter?
    var selectedAnnotationKey: String?
    var selectedAnnotationRect: CGRect?
    var documentSearchTerm: String?
    var comments: [String: NSAttributedString]
    var changes: Changes
    var error: Error?
    /// Updates that need to be performed on html/epub document
    var documentUpdate: DocumentUpdate?
    /// Annotation keys in sidebar that need to reload (for example cell height)
    var updatedAnnotationKeys: [String]?
    /// Annotation key to focus in annotation sidebar
    var focusSidebarKey: String?
    /// Annotation key to focus in document
    var focusDocumentKey: String?
    var selectedAnnotationCommentActive: Bool
    var sidebarEditingEnabled: Bool
    var notificationToken: NotificationToken?
    var deletionEnabled: Bool
    /// Selected annotations when annotations are being edited in sidebar
    var selectedAnnotationsDuringEditing: Set<String>

    init(url: URL, key: String, settings: HtmlEpubSettings, libraryId: LibraryIdentifier, userId: Int, username: String) {
        let originalFile = Files.file(from: url)
        let temporaryDirectory = Files.tmpReaderDirectory
        self.originalFile = originalFile
        readerFile = temporaryDirectory.copy(withName: "view", ext: "html")
        documentFile = temporaryDirectory.appending(relativeComponent: "content").copy(withName: originalFile.name, ext: originalFile.ext)
        self.key = key
        self.settings = settings
        self.userId = userId
        self.username = username
        commentFont = PDFReaderLayout.annotationLayout.font
        sortedKeys = []
        annotations = [:]
        comments = [:]
        sidebarEditingEnabled = false
        selectedAnnotationCommentActive = false
        toolColors = [
            .highlight: UIColor(hex: Defaults.shared.highlightColorHex),
            .note: UIColor(hex: Defaults.shared.noteColorHex)
        ]
        changes = []
        deletionEnabled = false
        selectedAnnotationsDuringEditing = []

        switch libraryId {
        case .custom:
            library = Library(identifier: libraryId, name: L10n.Libraries.myLibrary, metadataEditable: true, filesEditable: true)

        case .group:
            library = Library(identifier: libraryId, name: L10n.unknown, metadataEditable: false, filesEditable: false)
        }
    }

    mutating func cleanup() {
        documentData = nil
        documentUpdate = nil
        changes = []
        error = nil
        focusSidebarKey = nil
        focusDocumentKey = nil
        updatedAnnotationKeys = nil
    }
}
