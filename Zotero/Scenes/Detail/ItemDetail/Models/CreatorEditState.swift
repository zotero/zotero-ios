//
//  CreatorEditState.swift
//  Zotero
//
//  Created by Michal Rentka on 28/10/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CreatorEditState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let namePresentation = Changes(rawValue: 1 << 0)
        static let type = Changes(rawValue: 1 << 1)
    }

    let itemType: String

    var creator: ItemDetailState.Creator
    var changes: Changes

    init(itemType: String, creator: ItemDetailState.Creator) {
        self.itemType = itemType
        self.creator = creator
        self.changes = []
    }

    mutating func cleanup() {
        self.changes = []
    }
}
