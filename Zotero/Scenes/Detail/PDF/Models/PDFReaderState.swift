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
        static let itemObserving = Changes(rawValue: 1 << 8)
        static let export = Changes(rawValue: 1 << 9)
    }

    enum AppearanceMode: UInt {
        case automatic
        case light
        case dark
    }

    static let activeColorKey = "PDFReaderState.activeColor"

    let key: String
    let library: Library
    let document: Document
    let previewCache: NSCache<NSString, UIImage>
    let commentFont: UIFont
    let userId: Int
    let username: String

    var interfaceStyle: UIUserInterfaceStyle
    var annotations: [Int: [Annotation]]
    var annotationsSnapshot: [Int: [Annotation]]?
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
    var currentFilter: String?
    var changes: Changes
    var selectedAnnotation: Annotation?
    var selectedAnnotationCommentActive: Bool
    /// Location to focus in document
    var focusDocumentLocation: AnnotationDocumentLocation?
    /// Annotation key to focus in annotation sidebar
    var focusSidebarIndexPath: IndexPath?
    /// Index paths of annotations in sidebar that need to reload cell height
    var updatedAnnotationIndexPaths: [IndexPath]?
    /// Annotations that loaded their preview images and need to show them
    var loadedPreviewImageAnnotationKeys: Set<String>?
    /// Used when user interface style (dark mode) changes. Indicates that annotation previews need to be stored for new appearance
    /// if they are not available.
    var shouldStoreAnnotationPreviewsIfNeeded: Bool
    var visiblePage: Int
    var exportState: ExportState?
    /// Used to ignore next insertion/deletion notification of annotations. Used when there is a remote change of annotations. PSPDFKit can't suppress notifications when adding/deleting annotations
    /// to/from document. So when a remote change comes in, the document is edited and emits notifications which would try to do the same work again.
    var ignoreNotifications: [Notification.Name: Set<String>]
    var settings: PDFSettingsState

    init(url: URL, key: String, library: Library, settings: PDFSettingsState, userId: Int, username: String, interfaceStyle: UIUserInterfaceStyle) {
        self.key = key
        self.library = library
        self.userId = userId
        self.username = username
        self.interfaceStyle = interfaceStyle
        self.settings = settings
        self.deletedKeys = []
        self.insertedKeys = []
        self.modifiedKeys = []
        self.dbPositions = []
        self.previewCache = NSCache()
        self.document = Document(url: url)
        self.annotations = [:]
        self.comments = [:]
        self.ignoreNotifications = [:]
        self.selectedAnnotationCommentActive = false
        self.shouldStoreAnnotationPreviewsIfNeeded = false
        self.visiblePage = 0
        self.commentFont = PDFReaderLayout.annotationLayout.font
        self.activeColor = UserDefaults.standard.string(forKey: PDFReaderState.activeColorKey)
                                                .flatMap({ UIColor(hex: $0) }) ?? UIColor(hex: AnnotationsConfig.defaultActiveColor)
        self.changes = []
        self.previewCache.totalCostLimit = 1024 * 1024 * 10 // Cache object limit - 10 MB
    }

    mutating func cleanup() {
        self.changes = []
        self.exportState = nil
        self.focusDocumentLocation = nil
        self.focusSidebarIndexPath = nil
        self.updatedAnnotationIndexPaths = nil
        self.loadedPreviewImageAnnotationKeys = nil
    }
}

#endif
