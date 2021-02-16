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
        static let selectAll = Changes(rawValue: 1 << 3)
        static let attachmentsRemoved = Changes(rawValue: 1 << 4)
    }

    let type: ItemFetchType
    let library: Library

    var sortType: ItemsSortType
    var searchTerm: String?
    var results: Results<RItem>?
    // Cache of attachments so that they don't need to be re-created in tableView. The key is key of parent item, or item if it's a standalone attachment.
    var attachments: [String: Attachment]
    // Cache of DOIs so that they don't need to be re-fetched in tableView.
    var dois: [String: String]
    var selectedItems: Set<String>
    var isEditing: Bool
    var changes: Changes
    var error: ItemsError?
    var itemDuplication: RItem?
    var openAttachment: (Attachment, String)?
    // Used to indicate which row should update it's attachment view. The update is done directly to cell instead of tableView reload.
    var updateItemKey: String?

    init(type: ItemFetchType, library: Library, results: Results<RItem>?, sortType: ItemsSortType, error: ItemsError?) {
        self.type = type
        self.library = library
        self.results = results
        self.attachments = [:]
        self.dois = [:]
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
        self.openAttachment = nil
        self.updateItemKey = nil
    }
}
