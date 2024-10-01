//
//  TrashState.swift
//  Zotero
//
//  Created by Michal Rentka on 18.07.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import OrderedCollections

import RealmSwift

struct TrashState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let objects = Changes(rawValue: 1 << 0)
        static let editing = Changes(rawValue: 1 << 1)
        static let selection = Changes(rawValue: 1 << 2)
        static let selectAll = Changes(rawValue: 1 << 3)
        static let filters = Changes(rawValue: 1 << 4)
        static let batchData = Changes(rawValue: 1 << 5)
        static let attachmentsRemoved = Changes(rawValue: 1 << 6)
        static let library = Changes(rawValue: 1 << 7)
    }

    enum Error: Swift.Error {
        case dataLoading
    }

    var library: Library
    var libraryToken: NotificationToken?
    var itemResults: Results<RItem>?
    var itemsToken: NotificationToken?
    // Keys for all items are stored so that when a deletion comes in it can be determined which keys were deleted
    var itemKeys: [String]
    var collectionResults: Results<RCollection>?
    var collectionsToken: NotificationToken?
    // Keys for all collecitons are stored so that when a deletion comes in it can be determined which keys were deleted
    var collectionKeys: [String]
    var objects: OrderedDictionary<TrashKey, TrashObject>
    var snapshot: OrderedDictionary<TrashKey, TrashObject>?
    var sortType: ItemsSortType
    var searchTerm: String?
    var filters: [ItemsFilter]
    var isEditing: Bool
    var selectedItems: Set<TrashKey>
    var attachmentToOpen: String?
    var downloadBatchData: ItemsState.DownloadBatchData?
    // Used to indicate which row should update it's attachment view. The update is done directly to cell instead of tableView reload.
    var updateItemKey: TrashKey?
    var changes: Changes
    var error: ItemsError?
    var titleFont: UIFont {
        return UIFont.preferredFont(for: .headline, weight: .regular)
    }

    init(libraryId: LibraryIdentifier, sortType: ItemsSortType, searchTerm: String?, filters: [ItemsFilter], downloadBatchData: ItemsState.DownloadBatchData?) {
        objects = [:]
        self.sortType = sortType
        self.filters = filters
        self.searchTerm = searchTerm
        isEditing = false
        changes = []
        selectedItems = []
        itemKeys = []
        collectionKeys = []
        self.downloadBatchData = downloadBatchData

        switch libraryId {
        case .custom:
            library = Library(identifier: libraryId, name: L10n.Libraries.myLibrary, metadataEditable: true, filesEditable: true)

        case .group:
            library = Library(identifier: libraryId, name: L10n.unknown, metadataEditable: false, filesEditable: false)
        }
    }

    mutating func cleanup() {
        error = nil
        changes = []
        updateItemKey = nil
    }
}
