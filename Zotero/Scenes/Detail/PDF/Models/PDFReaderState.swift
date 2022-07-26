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
    struct Changes: OptionSet {
        typealias RawValue = UInt16

        let rawValue: UInt16

        static let annotations = Changes(rawValue: 1 << 0)
        static let selection = Changes(rawValue: 1 << 1)
        static let interfaceStyle = Changes(rawValue: 1 << 2)
        static let settings = Changes(rawValue: 1 << 3)
        static let activeColor = Changes(rawValue: 1 << 4)
        static let activeComment = Changes(rawValue: 1 << 5)
        static let save = Changes(rawValue: 1 << 6)
        static let itemObserving = Changes(rawValue: 1 << 7)
        static let export = Changes(rawValue: 1 << 8)
        static let activeLineWidth = Changes(rawValue: 1 << 9)
        static let sidebarEditing = Changes(rawValue: 1 << 10)
        static let sidebarEditingSelection = Changes(rawValue: 1 << 11)
        static let filter = Changes(rawValue: 1 << 12)
        static let activeEraserSize = Changes(rawValue: 1 << 13)
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

    var interfaceStyle: UIUserInterfaceStyle
    var annotationKeys: [Int: [String]]
    var annotations: [String: Annotation]
    var annotationKeysSnapshot: [Int: [String]]?
    /// These 3 sets of keys are stored for 2 purposes:
    /// 1. deletedKeys are used to remove only those annotations which were actually deleted in UI
    /// 2. If user edits the document, each save results in `Results<RItem>` observing notification, which leads to `.syncItems` action, which then tries to perform the same action again unnecessarily.
    ///    These keys are used by observing controller to skip those notifications.
    var deletedKeys: Set<String>
    var insertedKeys: Set<String>
    var modifiedKeys: Set<String>
    /// Array of annotation positions as they are returned from database. Used for diffing when an update from DB comes in.
    var dbPositions: [AnnotationPosition]
    var dbItems: Results<RItem>?
    var comments: [String: NSAttributedString]
    var activeColor: UIColor
    var activeLineWidth: CGFloat
    var activeEraserSize: CGFloat
    var changes: Changes
    var sidebarEditingEnabled: Bool
    /// Annotation selected when annotations are not being edited in sidebar
    var selectedAnnotationKey: String?
    var selectedAnnotation: Annotation? {
        return self.selectedAnnotationKey.flatMap({ self.annotations[$0] })
    }
    var selectedAnnotationCommentActive: Bool
    /// Annotations selected when annotations are being edited in sidebar
    var selectedAnnotationsDuringEditing: Set<String>
    var hasOneSelectedAnnotationDuringEditing: Bool {
        return self.selectedAnnotationsDuringEditing.count == 1
    }
    var deletionEnabled: Bool
    var mergingEnabled: Bool
    /// Location to focus in document
    var focusDocumentLocation: AnnotationDocumentLocation?
    /// Annotation key to focus in annotation sidebar
    var focusSidebarKey: String?
    /// Annotation keys in sidebar that need to reload cell height
    var updatedAnnotationKeys: [String]?
    /// Annotations that loaded their preview images and need to show them
    var loadedPreviewImageAnnotationKeys: Set<String>?
    /// Used when user interface style (dark mode) changes. Indicates that annotation previews need to be stored for new appearance
    /// if they are not available.
    var shouldStoreAnnotationPreviewsIfNeeded: Bool
    var visiblePage: Int
    var exportState: PDFExportState?
    /// Used to ignore next insertion/deletion notification of annotations. Used when there is a remote change of annotations. PSPDFKit can't suppress notifications when adding/deleting annotations
    /// to/from document. So when a remote change comes in, the document is edited and emits notifications which would try to do the same work again.
    var ignoreNotifications: [Notification.Name: Set<String>]
    var settings: PDFSettings
    var searchTerm: String?
    var filter: AnnotationsFilter?

    init(url: URL, key: String, library: Library, settings: PDFSettings, userId: Int, username: String, displayName: String, interfaceStyle: UIUserInterfaceStyle) {
        self.key = key
        self.library = library
        self.userId = userId
        self.username = username
        self.displayName = displayName
        self.interfaceStyle = interfaceStyle
        self.settings = settings
        self.deletedKeys = []
        self.insertedKeys = []
        self.modifiedKeys = []
        self.dbPositions = []
        self.previewCache = NSCache()
        self.document = Document(url: url)
        self.annotationKeys = [:]
        self.annotations = [:]
        self.comments = [:]
        self.ignoreNotifications = [:]
        self.selectedAnnotationCommentActive = false
        self.selectedAnnotationsDuringEditing = []
        self.deletionEnabled = false
        self.mergingEnabled = false
        self.shouldStoreAnnotationPreviewsIfNeeded = false
        self.sidebarEditingEnabled = false
        self.visiblePage = 0
        self.commentFont = PDFReaderLayout.annotationLayout.font
        self.activeColor = UIColor(hex: Defaults.shared.activeColorHex)
        self.activeLineWidth = CGFloat(Defaults.shared.activeLineWidth)
        self.activeEraserSize = CGFloat(Defaults.shared.activeEraserSize)
        self.changes = []
        self.previewCache.totalCostLimit = 1024 * 1024 * 10 // Cache object limit - 10 MB
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
