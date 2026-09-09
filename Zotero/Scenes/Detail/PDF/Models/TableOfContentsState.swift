//
//  TableOfContentsState.swift
//  Zotero
//
//  Created by Michal Rentka on 20.10.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

struct TableOfContentsChanges: OptionSet {
    typealias RawValue = UInt16

    let rawValue: UInt16

    static let snapshot = TableOfContentsChanges(rawValue: 1 << 0)
    static let currentOutline = TableOfContentsChanges(rawValue: 1 << 1)
}

struct TableOfContentsState<O: Outline>: ViewModelState {
    enum Row: Hashable {
        case searchBar
        case outline(outline: O, isActive: Bool, isCurrent: Bool)
    }

    var outlines: [O]
    var search: String
    var currentOutlineId: UUID?
    var changes: TableOfContentsChanges
    var outlineSnapshot: NSDiffableDataSourceSectionSnapshot<Row>?

    init(outlines: [O], currentOutlineId: UUID? = nil) {
        self.outlines = outlines
        self.currentOutlineId = currentOutlineId
        search = ""
        changes = []
    }

    mutating func cleanup() {
        changes = []
    }
}
