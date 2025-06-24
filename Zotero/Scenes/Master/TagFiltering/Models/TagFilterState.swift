//
//  TagFilterState.swift
//  Zotero
//
//  Created by Michal Rentka on 22.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct TagFilterState: ViewModelState {
    struct FilterTag: Hashable, Equatable {
        let tag: Tag
        let isActive: Bool
    }
    
    enum Error: Swift.Error {
        case loadingFailed
        case deletionFailed
        case tagAssignFailed
    }

    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let tags = Changes(rawValue: 1 << 0)
        static let selection = Changes(rawValue: 1 << 1)
        static let options = Changes(rawValue: 1 << 2)
    }

    var tags: [FilterTag]
    var snapshot: [FilterTag]?
    var selectedTags: Set<String>
    var searchTerm: String
    var showAutomatic: Bool
    var displayAll: Bool
    var error: Error?
    var automaticCount: Int?
    var changes: Changes

    init(selectedTags: Set<String>, showAutomatic: Bool, displayAll: Bool) {
        tags = []
        searchTerm = ""
        self.selectedTags = selectedTags
        self.showAutomatic = showAutomatic
        self.displayAll = displayAll
        changes = []
    }

    mutating func cleanup() {
        changes = []
        error = nil
        automaticCount = nil
    }
}
