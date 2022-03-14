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
        static let name = Changes(rawValue: 1 << 2)
    }

    let itemType: String

    var creator: ItemDetailState.Creator
    var changes: Changes
    var isValid: Bool {
        switch self.creator.namePresentation {
        case .full: return !self.creator.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .separate: return !self.creator.firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !self.creator.lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    init(itemType: String, creator: ItemDetailState.Creator) {
        self.itemType = itemType
        self.creator = creator
        self.changes = []
    }

    mutating func cleanup() {
        self.changes = []
    }
}
