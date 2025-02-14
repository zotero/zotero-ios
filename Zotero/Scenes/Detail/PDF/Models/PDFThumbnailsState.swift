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

        static let appearance = Changes(rawValue: 1 << 0)
        static let pages = Changes(rawValue: 1 << 1)
        static let selection = Changes(rawValue: 1 << 2)
        static let scrollToSelection = Changes(rawValue: 1 << 3)
        static let reload = Changes(rawValue: 1 << 4)
    }

    enum SelectionType {
        case fromDocument
        case fromSidebar
    }

    struct Page: Hashable {
        let id: UUID
        let title: String

        init(title: String) {
            self.id = UUID()
            self.title = title
        }
    }

    let thumbnailSize: CGSize
    let document: Document
    let key: String
    let libraryId: LibraryIdentifier

    let cache: NSCache<NSNumber, UIImage>
    var pages: [Page]
    var appearance: Appearance
    var loadedThumbnail: Int?
    var selectedPageIndex: Int
    var changes: Changes

    init(key: String, libraryId: LibraryIdentifier, document: Document, selectedPageIndex: Int, appearance: Appearance) {
        let cache = NSCache<NSNumber, UIImage>()
        cache.totalCostLimit = 1024 * 1024 * 5 // Cache object limit - 5 MB
        self.cache = cache
        self.thumbnailSize = CGSize(width: PDFThumbnailsLayout.cellImageHeight, height: PDFThumbnailsLayout.cellImageHeight)
        self.key = key
        self.libraryId = libraryId
        self.document = document
        self.selectedPageIndex = selectedPageIndex
        self.appearance = appearance
        self.changes = []
        self.pages = []
    }

    mutating func cleanup() {
        changes = []
        loadedThumbnail = nil
    }
}
