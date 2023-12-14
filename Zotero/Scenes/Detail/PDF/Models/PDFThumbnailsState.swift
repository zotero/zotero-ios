//
//  PDFThumbnailsState.swift
//  Zotero
//
//  Created by Michal Rentka on 04.12.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import PSPDFKit

struct PDFThumbnailsState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let userInterface = Changes(rawValue: 1 << 0)
        static let pages = Changes(rawValue: 1 << 1)
        static let selection = Changes(rawValue: 1 << 2)
        static let scrollToSelection = Changes(rawValue: 1 << 3)
    }

    enum SelectionType {
        case fromDocument
        case fromSidebar
    }

    let thumbnailSize: CGSize
    let document: Document
    let key: String
    let libraryId: LibraryIdentifier

    let cache: NSCache<NSNumber, UIImage>
    var pages: [String]
    var isDark: Bool
    var loadedThumbnail: Int?
    var selectedPageIndex: Int
    var changes: Changes

    init(key: String, libraryId: LibraryIdentifier, document: Document, selectedPageIndex: Int, isDark: Bool) {
        self.cache = NSCache()
        self.thumbnailSize = CGSize(width: PDFThumbnailsLayout.cellImageHeight, height: PDFThumbnailsLayout.cellImageHeight)
        self.key = key
        self.libraryId = libraryId
        self.document = document
        self.selectedPageIndex = selectedPageIndex
        self.isDark = isDark
        self.changes = []
        self.pages = []
    }

    mutating func cleanup() {
        self.changes = []
    }
}
