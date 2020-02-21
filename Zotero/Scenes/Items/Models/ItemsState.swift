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
    }

    enum ItemType {
        case all, trash, publications
        case collection(String, String) // Key, Title
        case search(String, String) // Key, Title

        var collectionKey: String? {
            switch self {
            case .collection(let key, _):
                return key
            default:
                return nil
            }
        }

        var isTrash: Bool {
            switch self {
            case .trash:
                return true
            default:
                return false
            }
        }
    }

    let type: ItemType
    let library: Library

    var sortType: ItemsSortType
    var results: Results<RItem>?
    var unfilteredResults: Results<RItem>?
    var selectedItems: Set<String>
    var isEditing: Bool
    var changes: Changes
    var error: ItemsError?
    var itemDuplication: RItem?

    init(type: ItemType, library: Library, results: Results<RItem>?, error: ItemsError?) {
        self.type = type
        self.library = library
        self.results = results
        self.error = error
        self.isEditing = false
        self.sortType = .default
        self.selectedItems = []
        self.changes = []
    }

    mutating func cleanup() {
        self.error = nil
        self.changes = []
        self.itemDuplication = nil
    }
}
