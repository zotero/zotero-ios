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
    }

    let key: String
    let library: Library

    var activeTool: AnnotationTool?
    var toolColors: [AnnotationTool: UIColor]
    var changes: Changes

    init(key: String, library: Library) {
        self.key = key
        self.library = library
        self.toolColors = [.highlight: UIColor(hex: Defaults.shared.highlightColorHex),
                           .note: UIColor(hex: Defaults.shared.noteColorHex)]
        self.changes = []
    }

    mutating func cleanup() {
        self.changes = []
    }
}
