//
//  AnnotationToolOptionsState.swift
//  Zotero
//
//  Created by Michal Rentka on 20.01.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct AnnotationToolOptionsState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let color = Changes(rawValue: 1 << 0)
        static let size = Changes(rawValue: 1 << 1)
    }

    var colorHex: String?
    var size: Float?
    var changes: Changes

    init(colorHex: String?, size: Float?) {
        self.colorHex = colorHex
        self.size = size
        self.changes = []
    }

    mutating func cleanup() {
        self.changes = []
    }
}
