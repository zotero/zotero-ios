//
//  ItemsState.swift
//  Zotero
//
//  Created by Michal Rentka on 21/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ItemsState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let results = Changes(rawValue: 1 << 0)
        static let editing = Changes(rawValue: 1 << 1)
        static let selection = Changes(rawValue: 1 << 2)
        static let sortType = Changes(rawValue: 1 << 3)
        static let selectAll = Changes(rawValue: 1 << 4)
    }

    let type: ItemFetchType
    let library: Library

    var sortType: ItemsSortType
    var results: Results<RItem>?
    var unfilteredResults: Results<RItem>?
    var selectedItems: Set<String>
    var isEditing: Bool
    var changes: Changes
    var error: ItemsError?
    var itemDuplication: RItem?

    init(type: ItemFetchType, library: Library, results: Results<RItem>?, sortType: ItemsSortType, error: ItemsError?) {
        self.type = type
        self.library = library
        self.results = results
        self.error = error
        self.isEditing = false
        self.selectedItems = []
        self.changes = []
        self.sortType = sortType
    }

    mutating func cleanup() {
        self.error = nil
        self.changes = []
        self.itemDuplication = nil
    }
}
