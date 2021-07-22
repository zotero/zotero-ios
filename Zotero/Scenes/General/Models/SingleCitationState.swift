//
//  SingleCitationState.swift
//  Zotero
//
//  Created by Michal Rentka on 15.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

struct SingleCitationState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let locator = Changes(rawValue: 1 << 0)
        static let preview = Changes(rawValue: 1 << 1)
        static let loading = Changes(rawValue: 1 << 2)
    }

    enum Error: Swift.Error {
        case cantPreloadWebView
    }

    static let locators: [String] = ["page", "book", "chapter", "column", "figure", "folio", "issue", "line", "note", "opus", "paragraph", "part", "section", "sub verbo", "verse", "volume"]

    let itemIds: Set<String>
    let libraryId: LibraryIdentifier
    let styleId: String
    let localeId: String

    var locator: String
    var locatorValue: String
    var omitAuthor: Bool
    var preview: String
    weak var webView: WKWebView?
    var error: Error?
    var changes: Changes

    init(itemIds: Set<String>, libraryId: LibraryIdentifier, styleId: String, localeId: String) {
        self.itemIds = itemIds
        self.libraryId = libraryId
        self.styleId = styleId
        self.localeId = localeId
        self.locator = SingleCitationState.locators.first!
        self.changes = []
        self.locatorValue = ""
        self.omitAuthor = false
        self.preview = ""
    }

    mutating func cleanup() {
        self.error =  nil
        self.changes = []
    }
}
