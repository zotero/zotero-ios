//
//  AllCollectionPickerState.swift
//  ZShare
//
//  Created by Michal Rentka on 11.02.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct AllCollectionPickerState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = Int8

        let rawValue: Int8

        init(rawValue: Int8) {
            self.rawValue = rawValue
        }

        static let results = Changes(rawValue: 1 << 0)
        static let search = Changes(rawValue: 1 << 1)
    }

    let selectedCollectionId: CollectionIdentifier
    let selectedLibraryId: LibraryIdentifier

    var libraries: [Library] = []
    var librariesCollapsed: [LibraryIdentifier: Bool] = [:]
    var trees: [LibraryIdentifier: CollectionTree] = [:]
    var searchTerm: String?
    var changes: Changes = []
    var toggledLibraryId: LibraryIdentifier?
    var toggledCollectionInLibraryId: LibraryIdentifier?

    mutating func cleanup() {
        self.changes = []
        self.toggledLibraryId = nil
        self.toggledCollectionInLibraryId = nil
    }
}
