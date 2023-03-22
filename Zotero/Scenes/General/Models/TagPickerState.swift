//
//  TagPickerState.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct TagPickerState: ViewModelState {
    enum Error: Swift.Error {
        case loadingFailed
    }

    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let tags = Changes(rawValue: 1 << 0)
        static let selection = Changes(rawValue: 1 << 1)
    }

    let libraryId: LibraryIdentifier

    var tags: [Tag]
    var snapshot: [Tag]?
    var selectedTags: Set<String>
    var searchTerm: String
    var showAddTagButton: Bool
    var addedTagName: String?
    var error: Error?
    var changes: Changes

    init(libraryId: LibraryIdentifier, selectedTags: Set<String>, tags: [Tag] = []) {
        self.libraryId = libraryId
        self.tags = tags
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
