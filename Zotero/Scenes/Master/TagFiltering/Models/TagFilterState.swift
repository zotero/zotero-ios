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
    enum Error: Swift.Error {
        case loadingFailed
    }

    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let tags = Changes(rawValue: 1 << 0)
        static let selection = Changes(rawValue: 1 << 1)
    }

    struct ObservedChange {
        let results: Results<RTag>
        let modifications: [Int]
        let insertions: [Int]
        let deletions: [Int]
    }

    var libraryId: LibraryIdentifier
    var collectionId: CollectionIdentifier
    var coloredResults: Results<RTag>?
    var coloredChange: ObservedChange?
    var coloredSnapshot: Results<RTag>?
    var coloredNotificationToken: NotificationToken?
    var otherResults: Results<RTag>?
    var otherChange: ObservedChange?
    var otherSnapshot: Results<RTag>?
    var otherNotificationToken: NotificationToken?
    var filteredResults: Results<RTag>?
    var selectedTags: Set<String>
    var searchTerm: String
    var error: Error?
    var changes: Changes

    init(libraryId: LibraryIdentifier, collectionId: CollectionIdentifier, selectedTags: Set<String>) {
        self.libraryId = libraryId
        self.collectionId = collectionId
        self.searchTerm = ""
        self.selectedTags = selectedTags
        self.changes = []
    }

    mutating func cleanup() {
        self.changes = []
        self.error = nil
        self.coloredChange = nil
        self.otherChange = nil
    }
}

