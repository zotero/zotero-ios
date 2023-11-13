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
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let activeTool = Changes(rawValue: 1 << 0)
        static let annotations = Changes(rawValue: 1 << 1)
        static let selection = Changes(rawValue: 1 << 2)
        static let activeComment = Changes(rawValue: 1 << 3)
        static let sidebarEditing = Changes(rawValue: 1 << 4)
        static let filter = Changes(rawValue: 1 << 5)
        static let toolColor = Changes(rawValue: 1 << 6)
    }

    struct DocumentData {
        enum Page {
            case html(scrollYPercent: Double)
            case epub(cfi: String)
        }

        let buffer: String
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
        case unknown
    }

    let url: URL
    let key: String
    let library: Library
    let userId: Int
    let username: String
    let commentFont: UIFont

    var documentData: DocumentData?
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
    var focusDocumentLocation: String?
    var selectedAnnotationCommentActive: Bool
    var sidebarEditingEnabled: Bool
    var notificationToken: NotificationToken?

    init(url: URL, key: String, library: Library, userId: Int, username: String) {
        self.url = url
        self.key = key
        self.library = library
        self.userId = userId
        self.username = username
        self.commentFont = PDFReaderLayout.annotationLayout.font
        self.sortedKeys = []
        self.annotations = [:]
        self.comments = [:]
        self.sidebarEditingEnabled = false
        self.selectedAnnotationCommentActive = false
        self.toolColors = [
            .highlight: UIColor(hex: Defaults.shared.highlightColorHex),
            .note: UIColor(hex: Defaults.shared.noteColorHex)
        ]
        self.changes = []
    }

    mutating func cleanup() {
        documentData = nil
        documentUpdate = nil
        changes = []
        error = nil
        focusSidebarKey = nil
        focusDocumentLocation = nil
        updatedAnnotationKeys = nil
    }
}
