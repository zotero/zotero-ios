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
    struct AnnotationKey: Equatable, Hashable, Identifiable {
        enum Kind: Equatable, Hashable {
            case database
            case document
        }

        let key: String
        let type: Kind

        var id: String {
            return self.key
        }
    }

    struct Changes: OptionSet {
        typealias RawValue = UInt32

        let rawValue: UInt32

        static let annotations = Changes(rawValue: 1 << 0)
        static let selection = Changes(rawValue: 1 << 1)
        static let interfaceStyle = Changes(rawValue: 1 << 2)
        static let settings = Changes(rawValue: 1 << 3)
        static let activeComment = Changes(rawValue: 1 << 4)
        static let export = Changes(rawValue: 1 << 5)
        static let activeLineWidth = Changes(rawValue: 1 << 6)
        static let sidebarEditing = Changes(rawValue: 1 << 7)
        static let sidebarEditingSelection = Changes(rawValue: 1 << 8)
        static let filter = Changes(rawValue: 1 << 9)
        static let activeEraserSize = Changes(rawValue: 1 << 10)
        static let initialDataLoaded = Changes(rawValue: 1 << 11)
        static let visiblePageFromDocument = Changes(rawValue: 1 << 12)
        static let visiblePageFromThumbnailList = Changes(rawValue: 1 << 13)
        static let selectionDeletion = Changes(rawValue: 1 << 14)
        static let activeFontSize = Changes(rawValue: 1 << 15)
        static let library = Changes(rawValue: 1 << 16)
        static let md5 = Changes(rawValue: 1 << 17)
    }

    enum Error: Swift.Error {
        case cantDeleteAnnotation
        case cantAddAnnotations
        case cantUpdateAnnotation
        case mergeTooBig
        case pageNotInt
        case unknown
        case documentEmpty
    }

    let key: String
    let parentKey: String?
    let document: PSPDFKit.Document
    let displayTitle: String?
    let previewCache: NSCache<NSString, UIImage>
    let commentFont: UIFont
    let userId: Int
    let username: String
    let displayName: String

    var library: Library
    var libraryToken: NotificationToken?
    var sortedKeys: [AnnotationKey]
    var snapshotKeys: [AnnotationKey]?
    var token: NotificationToken?
    var itemToken: NotificationToken?
    var databaseAnnotations: Results<RItem>!
    var documentAnnotations: [String: PDFDocumentAnnotation]
    var comments: [String: NSAttributedString]
    var searchTerm: String?
    var filter: AnnotationsFilter?
    var visiblePage: Int
    var exportState: PDFExportState?
    var settings: PDFSettings
    var changes: Changes
    var error: Error?
    var pdfNotification: Notification?

    /// Selected annotation when annotations are not being edited in sidebar
    var selectedAnnotationKey: AnnotationKey?
    var selectedAnnotation: PDFAnnotation? {
        return self.selectedAnnotationKey.flatMap({ self.annotation(for: $0) })
    }
    var selectedAnnotationCommentActive: Bool
    /// Selected annotations when annotations are being edited in sidebar
    var selectedAnnotationsDuringEditing: Set<PDFReaderState.AnnotationKey>

    var interfaceStyle: UIUserInterfaceStyle
    var sidebarEditingEnabled: Bool
    var toolColors: [PSPDFKit.Annotation.Tool: UIColor]
    var changedColorForTool: PSPDFKit.Annotation.Tool?
    var activeLineWidth: CGFloat
    var activeEraserSize: CGFloat
    var activeFontSize: CGFloat

    var deletionEnabled: Bool
    var mergingEnabled: Bool

    /// Location to focus in document
    var focusDocumentLocation: AnnotationDocumentLocation?
    /// Annotation key to focus in annotation sidebar
    var focusSidebarKey: AnnotationKey?
    /// Annotation keys in sidebar that need to reload (for example cell height)
    var updatedAnnotationKeys: [AnnotationKey]?
    /// Annotations that loaded their preview images and need to show them
    var loadedPreviewImageAnnotationKeys: Set<String>?
    /// Page that should be shown initially, instead of stored page
    var initialPage: Int?
    var unlockSuccessful: Bool?

    init(
        url: URL,
        key: String,
        parentKey: String?,
        displayTitle: String?,
        libraryId: LibraryIdentifier,
        initialPage: Int?,
        preselectedAnnotationKey: String?,
        settings: PDFSettings,
        userId: Int,
        username: String,
        displayName: String,
        interfaceStyle: UIUserInterfaceStyle
    ) {
        self.key = key
        self.parentKey = parentKey
        self.document = Document(url: url)
        self.displayTitle = displayTitle
        self.previewCache = NSCache()
        self.commentFont = PDFReaderLayout.annotationLayout.font
        self.userId = userId
        self.username = username
        self.displayName = displayName
        self.sortedKeys = []
        self.documentAnnotations = [:]
        self.comments = [:]
        self.visiblePage = 0
        self.initialPage = initialPage
        self.settings = settings
        self.selectedAnnotationKey = preselectedAnnotationKey.flatMap({ AnnotationKey(key: $0, type: .database) })
        self.changes = []
        self.selectedAnnotationCommentActive = false
        self.selectedAnnotationsDuringEditing = []
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
        self.deletionEnabled = false
        self.mergingEnabled = false

        self.previewCache.totalCostLimit = 1024 * 1024 * 10 // Cache object limit - 10 MB

        switch libraryId {
        case .custom:
            library = Library(identifier: libraryId, name: L10n.Libraries.myLibrary, metadataEditable: true, filesEditable: true)

        case .group:
            library = Library(identifier: libraryId, name: L10n.unknown, metadataEditable: false, filesEditable: false)
        }
    }

    func annotation(for key: AnnotationKey) -> PDFAnnotation? {
        switch key.type {
        case .database:
            return self.databaseAnnotations.filter(.key(key.key)).first.flatMap({ PDFDatabaseAnnotation(item: $0) })

        case .document:
            return self.documentAnnotations[key.key]
        }
    }

    func hasAnnotation(with key: String) -> Bool {
        if self.documentAnnotations[key] != nil {
            return true
        }
        if self.databaseAnnotations.filter(.key(key)).first != nil {
            return true
        }
        return false
    }

    mutating func cleanup() {
        self.changes = []
        self.exportState = nil
        self.focusDocumentLocation = nil
        self.focusSidebarKey = nil
        self.updatedAnnotationKeys = nil
        self.loadedPreviewImageAnnotationKeys = nil
        self.error = nil
        self.pdfNotification = nil
        self.changedColorForTool = nil
        self.unlockSuccessful = nil
    }
}
