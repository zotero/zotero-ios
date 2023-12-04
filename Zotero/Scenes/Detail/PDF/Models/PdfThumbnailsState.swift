//
//  PdfThumbnailsState.swift
//  Zotero
//
//  Created by Michal Rentka on 04.12.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import PSPDFKit

struct PdfThumbnailsState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let userInterface = Changes(rawValue: 1 << 0)
    }

    let thumbnailSize: CGSize
    let document: Document
    let key: String
    let libraryId: LibraryIdentifier

    let cache: NSCache<NSNumber, UIImage>
    var isDark: Bool
    var loadedThumbnail: UInt?
    var changes: Changes

    init(key: String, libraryId: LibraryIdentifier, document: Document, isDark: Bool) {
        self.cache = NSCache()
        self.thumbnailSize = CGSize(width: 100, height: 100)
        self.key = key
        self.libraryId = libraryId
        self.document = document
        self.isDark = isDark
        self.changes = []
    }

    mutating func cleanup() {
        self.changes = []
    }
}

