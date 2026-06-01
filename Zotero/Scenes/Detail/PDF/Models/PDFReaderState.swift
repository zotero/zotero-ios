//
//  PDFReaderState.swift
//  Zotero
//
//  Created by Michal Rentka on 29/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKit
import PSPDFKitUI
import RealmSwift

typealias AnnotationDocumentLocation = (page: Int, boundingBox: CGRect)

struct PDFReaderState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt32

        let rawValue: UInt32

        static let annotations = Changes(rawValue: 1 << 0)
        static let selection = Changes(rawValue: 1 << 1)
        static let settings = Changes(rawValue: 1 << 2)
        static let export = Changes(rawValue: 1 << 3)
        static let activeLineWidth = Changes(rawValue: 1 << 4)
        static let activeEraserSize = Changes(rawValue: 1 << 5)
        static let initialDataLoaded = Changes(rawValue: 1 << 6)
        static let visiblePageFromDocument = Changes(rawValue: 1 << 7)
        static let visiblePageFromThumbnailList = Changes(rawValue: 1 << 8)
        static let visiblePage = Changes(rawValue: 1 << 9)
        static let selectionDeletion = Changes(rawValue: 1 << 10)
        static let activeFontSize = Changes(rawValue: 1 << 11)
        static let library = Changes(rawValue: 1 << 12)
        static let md5 = Changes(rawValue: 1 << 13)
        static let appearance = Changes(rawValue: 1 << 14)
    }

    enum Error: ReaderError {
        case cantDeleteAnnotation
        case cantAddAnnotations
        case cantUpdateAnnotation
        case mergeTooBig
        case pageNotInt
        case unknown
        case documentEmpty
        case unknownLoading

        var title: String {
            switch self {
            case .cantDeleteAnnotation, .cantAddAnnotations, .cantUpdateAnnotation, .pageNotInt, .unknown, .documentEmpty, .unknownLoading:
                return L10n.error

            case .mergeTooBig:
                return L10n.Errors.Pdf.mergeTooBigTitle
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

            case .mergeTooBig:
                return L10n.Errors.Pdf.mergeTooBig

            case .pageNotInt:
                return L10n.Errors.Pdf.pageIndexNotInt

            case .unknown, .unknownLoading:
                return L10n.Errors.unknown

            case .documentEmpty:
                return L10n.Errors.Pdf.emptyDocument
            }
        }
        
        var documentShouldClose: Bool {
            switch self {
            case .documentEmpty, .pageNotInt, .unknownLoading:
                return true
                
            case .cantDeleteAnnotation, .cantAddAnnotations, .cantUpdateAnnotation, .mergeTooBig, .unknown:
                return false
            }
        }
    }

    let key: String
    let parentKey: String?
    let document: PSPDFKit.Document
    let title: String?
    let userId: Int
    let username: String

    var library: Library
    var libraryToken: NotificationToken?
    var annotationPages: IndexSet
    var token: NotificationToken?
    var itemToken: NotificationToken?
    var databaseAnnotations: Results<RItem>!
    var documentAnnotations: Results<RDocumentAnnotation>?
    var defaultAnnotationPageLabel: DefaultAnnotationPageLabel
    var texts: [String: (String, [UIFont: NSAttributedString])]
    var comments: [String: NSAttributedString]
    var searchTerm: String?
    var filter: AnnotationsFilter?
    var visiblePage: Int
    var exportState: PDFExportState?
    var settings: PDFSettings
    var changes: Changes
    var error: Error?
    var pdfNotification: Notification?
    var documentMD5Changed: Bool?

    /// Selected annotation when annotations are not being edited in sidebar
    var selectedAnnotationKey: PDFReaderAnnotationKey?
    var selectedAnnotation: PDFAnnotation? {
        return self.selectedAnnotationKey.flatMap({ self.annotation(for: $0) })
    }
    var selectedAnnotationCommentActive: Bool

    var interfaceStyle: UIUserInterfaceStyle
    var sidebarEditingEnabled: Bool
    var toolColors: [PSPDFKit.Annotation.Tool: UIColor]
    var changedColorForTool: PSPDFKit.Annotation.Tool?
    var activeLineWidth: CGFloat
    var activeEraserSize: CGFloat
    var activeFontSize: CGFloat

    /// Location to focus in document
    var focusDocumentLocation: AnnotationDocumentLocation?
    /// Whether the latest selection originated in the document and should be focused in the sidebar.
    var selectionFromDocument: Bool
    /// Annotation keys changed by the latest annotation update.
    var changedAnnotationKeys: [PDFReaderAnnotationKey]?
    /// Page that should be shown initially, instead of stored page
    var initialPage: Int?
    /// Rects that should be highlighted initially, used by note editor to highlight original annotation position
    var previewRects: [CGRect]?
    var unlockSuccessful: Bool?
    var unlockPassword: String?

    init(
        url: URL,
        key: String,
        parentKey: String?,
        title: String?,
        libraryId: LibraryIdentifier,
        initialPage: Int?,
        preselectedAnnotationKey: String?,
        previewRects: [CGRect]?,
        settings: PDFSettings,
        userId: Int,
        username: String,
        interfaceStyle: UIUserInterfaceStyle
    ) {
        self.key = key
        self.parentKey = parentKey
        self.document = Document(url: url)
        document.overrideClass(PSPDFKit.AnnotationManager.self, with: AnnotationManager.self)
        document.overrideClass(PSPDFKit.HighlightAnnotation.self, with: HighlightAnnotation.self)
        document.overrideClass(PSPDFKit.NoteAnnotation.self, with: NoteAnnotation.self)
        document.overrideClass(PSPDFKit.SquareAnnotation.self, with: SquareAnnotation.self)
        document.overrideClass(PSPDFKit.UnderlineAnnotation.self, with: UnderlineAnnotation.self)
        document.overrideClass(PSPDFKitUI.FreeTextAnnotationView.self, with: FreeTextAnnotationView.self)
        self.title = title
        self.userId = userId
        self.username = username
        self.annotationPages = IndexSet()
        self.documentAnnotations = nil
        self.defaultAnnotationPageLabel = .commonPageOffset(offset: 1)
        self.texts = [:]
        self.comments = [:]
        self.visiblePage = 0
        self.initialPage = initialPage
        self.settings = settings
        self.selectedAnnotationKey = preselectedAnnotationKey.flatMap({ PDFReaderAnnotationKey(key: $0, type: .database) })
        self.previewRects = previewRects
        self.unlockPassword = nil
        self.changes = []
        self.selectedAnnotationCommentActive = false
        self.interfaceStyle = interfaceStyle
        self.sidebarEditingEnabled = false
        self.toolColors = [
            .highlight: UIColor(hex: Defaults.shared.highlightColorHex),
            .square: UIColor(hex: Defaults.shared.squareColorHex),
            .note: UIColor(hex: Defaults.shared.noteColorHex),
            .ink: UIColor(hex: Defaults.shared.inkColorHex),
            .underline: UIColor(hex: Defaults.shared.underlineColorHex),
            .freeText: UIColor(hex: Defaults.shared.textColorHex)
        ]
        self.activeLineWidth = CGFloat(Defaults.shared.activeLineWidth)
        self.activeEraserSize = CGFloat(Defaults.shared.activeEraserSize)
        self.activeFontSize = CGFloat(Defaults.shared.activeFontSize)
        self.selectionFromDocument = false

        switch libraryId {
        case .custom:
            library = Library(identifier: libraryId, name: L10n.Libraries.myLibrary, metadataEditable: true, filesEditable: true)

        case .group:
            library = Library(identifier: libraryId, name: L10n.unknown, metadataEditable: false, filesEditable: false)
        }
    }

    func annotation(for key: PDFReaderAnnotationKey) -> PDFAnnotation? {
        switch key.type {
        case .database:
            return databaseAnnotations.filter(.key(key.key)).first.flatMap({ PDFDatabaseAnnotation(item: $0) })

        case .document:
            return documentAnnotations?.filter(.key(key.key)).first.flatMap({ PDFDocumentAnnotation(annotation: $0, displayName: displayName, username: username) })
        }
    }

    mutating func cleanup() {
        self.changes = []
        self.exportState = nil
        self.focusDocumentLocation = nil
        selectionFromDocument = false
        self.changedAnnotationKeys = nil
        self.error = nil
        self.pdfNotification = nil
        self.changedColorForTool = nil
        self.unlockSuccessful = nil
    }
}

extension PDFReaderState: ReaderState {
    var selectedReaderAnnotation: (any ReaderAnnotation)? {
        return selectedAnnotation
    }
}
