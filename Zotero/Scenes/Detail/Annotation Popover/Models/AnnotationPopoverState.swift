//
//  AnnotationPopoverState.swift
//  Zotero
//
//  Created by Michal Rentka on 30.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct AnnotationPopoverState: ViewModelState {
    struct Data {
        let libraryId: LibraryIdentifier
        let type: AnnotationType
        let isEditable: Bool
        let author: String
        let comment: NSAttributedString
        let color: String
        let lineWidth: CGFloat
        let pageLabel: String
        let highlightText: NSAttributedString
        let highlightFont: UIFont
        let tags: [Tag]
        let showsDeleteButton: Bool
    }

    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let comment = Changes(rawValue: 1 << 0)
        static let color = Changes(rawValue: 1 << 1)
        static let lineWidth = Changes(rawValue: 1 << 2)
        static let pageLabel = Changes(rawValue: 1 << 3)
        static let highlight = Changes(rawValue: 1 << 4)
        static let tags = Changes(rawValue: 1 << 5)
        static let deletion = Changes(rawValue: 1 << 6)
    }

    let libraryId: LibraryIdentifier
    let type: AnnotationType
    let isEditable: Bool
    let author: String
    let showsDeleteButton: Bool

    var comment: NSAttributedString
    var color: String
    var lineWidth: CGFloat
    var pageLabel: String
    var highlightText: NSAttributedString
    var highlightFont: UIFont
    var updateSubsequentLabels: Bool
    var tags: [Tag]
    var changes: Changes

    init(data: Data) {
        self.libraryId = data.libraryId
        self.type = data.type
        self.isEditable = data.isEditable
        self.author = data.author
        self.comment = data.comment
        self.color = data.color
        self.lineWidth = data.lineWidth
        self.pageLabel = data.pageLabel
        self.highlightText = data.highlightText
        self.highlightFont = data.highlightFont
        self.tags = data.tags
        self.showsDeleteButton = data.showsDeleteButton
        self.updateSubsequentLabels = false
        self.changes = []
    }

    mutating func cleanup() {
        self.changes = []
    }
}
