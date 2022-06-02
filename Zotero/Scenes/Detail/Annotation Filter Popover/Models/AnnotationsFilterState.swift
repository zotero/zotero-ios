//
//  AnnotationsFilterState.swift
//  Zotero
//
//  Created by Michal Rentka on 01.06.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct AnnotationsFilterState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let colors = Changes(rawValue: 1 << 0)
        static let tags = Changes(rawValue: 1 << 1)
    }

    let availableColors: [String]
    let availableTags: [Tag]

    var colors: Set<String>
    var tags: Set<String>
    var changes: Changes

    init(filter: AnnotationsFilter?, availableColors: [String], availableTags: [Tag]) {
        self.colors = filter?.colors ?? []
        self.tags = filter?.tags ?? []
        self.availableColors = availableColors
        self.availableTags = availableTags
        self.changes = []
    }

    mutating func cleanup() {
        self.changes = []
    }
}
