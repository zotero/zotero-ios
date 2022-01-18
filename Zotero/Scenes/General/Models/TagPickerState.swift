//
//  TagPickerState.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct TagPickerState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let tags = Changes(rawValue: 1 << 0)
    }

    let libraryId: LibraryIdentifier
    var tags: [Tag]
    var snapshot: [Tag]?
    var selectedTags: Set<String>
    var searchTerm: String
    var showAddTagButton: Bool
    var addedTagName: String?
    var error: TagPickerError?
    var changes: Changes

    init(libraryId: LibraryIdentifier, selectedTags: Set<String>) {
        self.libraryId = libraryId
        self.tags = []
        self.searchTerm = ""
        self.selectedTags = selectedTags
        self.showAddTagButton = false
        self.changes = []
    }

    mutating func cleanup() {
        self.changes = []
        self.error = nil
        self.addedTagName = nil
    }
}
