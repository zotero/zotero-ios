//
//  AnnotationEditState.swift
//  Zotero
//
//  Created by Michal Rentka on 30.11.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct AnnotationEditState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let color = Changes(rawValue: 1 << 0)
        static let pageLabel = Changes(rawValue: 1 << 1)
    }

    var annotation: Annotation
    var updateSubsequentLabels: Bool
    var changes: Changes

    init(annotation: Annotation) {
        self.annotation = annotation
        self.updateSubsequentLabels = false
        self.changes = []
    }

    mutating func cleanup() {
        self.changes = []
    }
}
