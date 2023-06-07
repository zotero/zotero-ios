//
//  AnnotationEditState.swift
//  Zotero
//
//  Created by Michal Rentka on 30.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct AnnotationEditState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let color = Changes(rawValue: 1 << 0)
        static let pageLabel = Changes(rawValue: 1 << 1)
    }

    let key: PDFReaderState.AnnotationKey
    let type: AnnotationType
    let isEditable: Bool

    var color: String
    var lineWidth: CGFloat
    var pageLabel: String
    var highlightText: String
    var updateSubsequentLabels: Bool
    var changes: Changes

    init(annotation: Annotation, userId: Int, library: Library) {
        self.key = annotation.readerKey
        self.type = annotation.type
        self.isEditable = annotation.editability(currentUserId: userId, library: library) == .editable
        self.color = annotation.color
        self.lineWidth = annotation.lineWidth ?? 0
        self.pageLabel = annotation.pageLabel
        self.highlightText = annotation.text ?? ""
        self.updateSubsequentLabels = false
        self.changes = []
    }

    mutating func cleanup() {
        self.changes = []
    }
}
