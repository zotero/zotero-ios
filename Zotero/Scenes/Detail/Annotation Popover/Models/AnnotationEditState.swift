//
//  AnnotationEditState.swift
//  Zotero
//
//  Created by Michal Rentka on 30.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct AnnotationEditState: ViewModelState {
    struct AnnotationData {
        let type: AnnotationType
        let isEditable: Bool
        let color: String
        let lineWidth: CGFloat
        let pageLabel: String
        let highlightText: String
    }

    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let color = Changes(rawValue: 1 << 0)
        static let pageLabel = Changes(rawValue: 1 << 1)
    }

    let type: AnnotationType
    let isEditable: Bool

    var color: String
    var lineWidth: CGFloat
    var pageLabel: String
    var highlightText: String
    var updateSubsequentLabels: Bool
    var changes: Changes

    init(data: AnnotationData) {
        self.type = data.type
        self.isEditable = data.isEditable
        self.color = data.color
        self.lineWidth = data.lineWidth
        self.pageLabel = data.pageLabel
        self.highlightText = data.highlightText
        self.updateSubsequentLabels = false
        self.changes = []
    }

    mutating func cleanup() {
        self.changes = []
    }
}
