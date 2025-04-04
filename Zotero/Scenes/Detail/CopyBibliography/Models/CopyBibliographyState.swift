//
//  CopyBibliographyState.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 27/12/23.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct CopyBibliographyState: ViewModelState {
    let itemIds: Set<String>
    let libraryId: LibraryIdentifier
    let styleId: String
    let localeId: String
    let exportAsHtml: Bool

    var citationSession: CitationController.Session?
    var processingBibliography = false
    var error: Error?

    init(itemIds: Set<String>, libraryId: LibraryIdentifier, styleId: String, localeId: String, exportAsHtml: Bool) {
        self.itemIds = itemIds
        self.libraryId = libraryId
        self.styleId = styleId
        self.localeId = localeId
        self.exportAsHtml = exportAsHtml
    }
    mutating func cleanup() {
        error = nil
    }
}
