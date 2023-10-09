//
//  HtmlEpubReaderState.swift
//  Zotero
//
//  Created by Michal Rentka on 14.09.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct HtmlEpubReaderState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let activeTool = Changes(rawValue: 1 << 0)
        static let annotations = Changes(rawValue: 1 << 1)
    }

    struct DocumentData {
        let buffer: String
        let annotationsJson: String
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

    var documentData: DocumentData?
    var activeTool: AnnotationTool?
    var toolColors: [AnnotationTool: UIColor]
    var annotations: [HtmlEpubAnnotation]
    var changes: Changes
    var error: Error?

    init(url: URL, key: String, library: Library, userId: Int, username: String) {
        self.url = url
        self.key = key
        self.library = library
        self.userId = userId
        self.username = username
        self.annotations = []
        self.toolColors = [
            .highlight: UIColor(hex: Defaults.shared.highlightColorHex),
            .note: UIColor(hex: Defaults.shared.noteColorHex)
        ]
        self.changes = []
    }

    mutating func cleanup() {
        documentData = nil
        changes = []
        error = nil
    }
}
