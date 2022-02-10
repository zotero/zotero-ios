//
//  CollectionsPickerState.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct CollectionsPickerState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let results = Changes(rawValue: 1 << 0)
        static let selection = Changes(rawValue: 1 << 1)
    }

    enum Error: Swift.Error {
        case dataLoading
    }

    let library: Library
    let excludedKeys: Set<String>

    var collectionTree: CollectionTree
    var error: Error?
    var changes: Changes
    var token: NotificationToken?
    var selected: Set<String>

    init(library: Library, excludedKeys: Set<String>, selected: Set<String>) {
        self.library = library
        self.excludedKeys = excludedKeys
        self.selected = selected
        self.changes = []
        self.collectionTree = CollectionTree(nodes: [], collections: [:], collapsed: [:])
    }

    mutating func cleanup() {
        self.changes = []
        self.error = nil
    }
}
