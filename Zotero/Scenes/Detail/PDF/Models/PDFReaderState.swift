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
        typealias RawValue = UInt16

        let rawValue: UInt16

        static let annotations = Changes(rawValue: 1 << 0)
        static let selection = Changes(rawValue: 1 << 1)
        static let interfaceStyle = Changes(rawValue: 1 << 2)
        static let settings = Changes(rawValue: 1 << 3)
        static let activeColor = Changes(rawValue: 1 << 4)
        static let activeComment = Changes(rawValue: 1 << 5)
        static let export = Changes(rawValue: 1 << 6)
        static let activeLineWidth = Changes(rawValue: 1 << 7)
        static let sidebarEditing = Changes(rawValue: 1 << 8)
        static let sidebarEditingSelection = Changes(rawValue: 1 << 9)
        static let filter = Changes(rawValue: 1 << 10)
        static let activeEraserSize = Changes(rawValue: 1 << 11)
    }

    enum AppearanceMode: UInt {
        case light
        case dark
        case automatic
    }

    let key: String
    let library: Library
    let document: PSPDFKit.Document
    let previewCache: NSCache<NSString, UIImage>
    let commentFont: UIFont
    let userId: Int
    let username: String
    let displayName: String

    var sortedKeys: [AnnotationKey]
    var snapshotKeys: [AnnotationKey]?
    var liveAnnotations: Results<RItem>!
    var token: NotificationToken?
    var databaseAnnotations: Results<RItem>!
    var documentAnnotations: [String: DocumentAnnotation]
    var comments: [String: NSAttributedString]
    var searchTerm: String?
    var filter: AnnotationsFilter?
    var visiblePage: Int
    var exportState: PDFExportState?
    var settings: PDFSettings
    var changes: Changes

    /// Selected annotation when annotations are not being edited in sidebar
    var selectedAnnotationKey: AnnotationKey?
    var selectedAnnotation: Annotation? {
        return self.selectedAnnotationKey.flatMap({ self.annotation(for: $0) })
    }
    var selectedAnnotationCommentActive: Bool
    /// Selected annotations when annotations are being edited in sidebar
    var selectedAnnotationsDuringEditing: Set<PDFReaderState.AnnotationKey>

    var interfaceStyle: UIUserInterfaceStyle
    var sidebarEditingEnabled: Bool
    var activeColor: UIColor
    var activeLineWidth: CGFloat
    var activeEraserSize: CGFloat

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
    /// Used when user interface style (dark mode) changes. Indicates that annotation previews need to be stored for new appearance
    /// if they are not available.
    var shouldStoreAnnotationPreviewsIfNeeded: Bool

    init(url: URL, key: String, library: Library, settings: PDFSettings, userId: Int, username: String, displayName: String, interfaceStyle: UIUserInterfaceStyle) {
        self.key = key
        self.library = library
        self.document = Document(url: url)
        self.previewCache = NSCache()
        self.commentFont = PDFReaderLayout.annotationLayout.font
        self.userId = userId
        self.username = username
        self.displayName = displayName
        self.sortedKeys = []
        self.documentAnnotations = [:]
        self.comments = [:]
        self.visiblePage = 0
        self.settings = settings
        self.changes = []
        self.selectedAnnotationCommentActive = false
        self.selectedAnnotationsDuringEditing = []
        self.interfaceStyle = interfaceStyle
        self.sidebarEditingEnabled = false
        self.activeColor = UIColor(hex: Defaults.shared.activeColorHex)
        self.activeLineWidth = CGFloat(Defaults.shared.activeLineWidth)
        self.activeEraserSize = CGFloat(Defaults.shared.activeEraserSize)
        self.deletionEnabled = false
        self.mergingEnabled = false
        self.shouldStoreAnnotationPreviewsIfNeeded = false

        self.previewCache.totalCostLimit = 1024 * 1024 * 10 // Cache object limit - 10 MB
    }

    func annotation(for key: AnnotationKey) -> Annotation? {
        switch key.type {
        case .database:
            return self.databaseAnnotations.filter(.key(key.key)).first.flatMap({ DatabaseAnnotation(item: $0) })
        case .document:
            return self.documentAnnotations[key.key]
        }
    }

    mutating func cleanup() {
        self.changes = []
        self.exportState = nil
        self.focusDocumentLocation = nil
        self.focusSidebarKey = nil
        self.updatedAnnotationKeys = nil
        self.loadedPreviewImageAnnotationKeys = nil
    }
}

#endif
