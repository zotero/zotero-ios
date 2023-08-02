//
//  AnnotationEditState.swift
//  Zotero
//
//  Created by Michal Rentka on 30.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct AnnotationEditState: ViewModelState {
    struct Data {
        let type: AnnotationType
        let isEditable: Bool
        let color: String
        let lineWidth: CGFloat
        let pageLabel: String
        let highlightText: String
        let fontSize: UInt?
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
    var fontSize: UInt
    var highlightText: String
    var updateSubsequentLabels: Bool
    var changes: Changes

    init(data: Data) {
        type = data.type
        isEditable = data.isEditable
        color = data.color
        lineWidth = data.lineWidth
        pageLabel = data.pageLabel
        highlightText = data.highlightText
        fontSize = data.fontSize ?? 0
        updateSubsequentLabels = false
        changes = []
    }

    mutating func cleanup() {
        changes = []
    }
}
