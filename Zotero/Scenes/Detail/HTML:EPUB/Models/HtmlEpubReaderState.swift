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
        static let popover = Changes(rawValue: 1 << 10)
        static let md5 = Changes(rawValue: 1 << 11)
        static let library = Changes(rawValue: 1 << 12)
        static let outline = Changes(rawValue: 1 << 13)
        static let appearance = Changes(rawValue: 1 << 14)
        static let searchResults = Changes(rawValue: 1 << 15)
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
        let selectedAnnotationKey: String?
    }

    struct DocumentUpdate {
        let deletions: [String]
        let insertions: [[String: Any]]
        let modifications: [[String: Any]]
    }

    struct Outline {
        let title: String
        let location: [String: Any]
        let children: [Outline]
    }

    enum Error: ReaderError {
        case cantDeleteAnnotation
        case cantAddAnnotations
        case cantUpdateAnnotation
        case incompatibleDocument
        case unknown

        var title: String {
            switch self {
            case .cantDeleteAnnotation, .cantAddAnnotations, .cantUpdateAnnotation, .incompatibleDocument, .unknown:
                return L10n.error
            }
        }

        var message: String {
            switch self {
            case .cantDeleteAnnotation:
                return L10n.Errors.Pdf.cantDeleteAnnotations

            case .cantAddAnnotations:
                return L10n.Errors.Pdf.cantAddAnnotations

            case .cantUpdateAnnotation:
                return L10n.Errors.Pdf.cantUpdateAnnotation

            case .incompatibleDocument:
                return L10n.Errors.Pdf.incompatibleDocument

            case .unknown:
                return L10n.Errors.unknown
            }
        }
        
        var documentShouldClose: Bool {
            return false
        }
    }

    let readerURL: URL?
    let originalFile: File
    let readerDirectory: File
    let documentFile: File
    let key: String
    let parentKey: String?
    let title: String?
    let userId: Int
    let username: String

    var library: Library
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
    var selectedAnnotationCommentActive: Bool
    /// Selected annotations when annotations are being edited in sidebar
    var selectedAnnotationsDuringEditing: Set<String>
    /// Temporary params of selected text, used to create highlight/underline with UIMenu buttons
    var selectedTextParams: [String: Any]?
    var annotationPopoverKey: String?
    var annotationPopoverRect: CGRect?
    var documentSearchTerm: String?
    var documentSearchResults: [DocumentSearchResult]
    var comments: [String: NSAttributedString]
    var texts: [String: (String, [UIFont: NSAttributedString])]
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
    var sidebarEditingEnabled: Bool
    var itemToken: NotificationToken?
    var annotationsToken: NotificationToken?
    var libraryToken: NotificationToken?
    var deletionEnabled: Bool
    var outlines: [Outline]
    var outlineSearch: String
    var interfaceStyle: UIUserInterfaceStyle

    var readerFile: File {
        readerDirectory.copy(withName: "view", ext: "html")
    }

    init(
        readerURL: URL?,
        url: URL,
        key: String,
        parentKey: String?,
        title: String?,
        preselectedAnnotationKey: String?,
        settings: HtmlEpubSettings,
        libraryId: LibraryIdentifier,
        userId: Int,
        username: String,
        interfaceStyle: UIUserInterfaceStyle
    ) {
        self.readerURL = readerURL ?? Bundle.main.url(forResource: "reader", withExtension: nil, subdirectory: "Bundled")
        let originalFile = Files.file(from: url)
        self.originalFile = originalFile
        readerDirectory = Files.temporaryDirectory
        documentFile = readerDirectory.appending(relativeComponent: "content").copy(withName: originalFile.name, ext: originalFile.ext)
        self.key = key
        self.parentKey = parentKey
        self.title = title
        self.settings = settings
        self.userId = userId
        self.username = username
        self.interfaceStyle = interfaceStyle
        selectedAnnotationKey = preselectedAnnotationKey
        sortedKeys = []
        annotations = [:]
        comments = [:]
        texts = [:]
        sidebarEditingEnabled = false
        selectedAnnotationCommentActive = false
        toolColors = [
            .highlight: UIColor(hex: Defaults.shared.highlightColorHex),
            .underline: UIColor(hex: Defaults.shared.underlineColorHex),
            .note: UIColor(hex: Defaults.shared.noteColorHex)
        ]
        changes = []
        deletionEnabled = false
        selectedAnnotationsDuringEditing = []
        outlines = []
        outlineSearch = ""
        documentSearchResults = []

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

extension HtmlEpubReaderState: ReaderState {
    var selectedReaderAnnotation: ReaderAnnotation? {
        return annotationPopoverKey.flatMap({ annotations[$0] })
    }
}
