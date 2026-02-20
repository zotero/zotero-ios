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
    struct Snapshot {
        let sortedKeys: [TrashKey]
        let keyToIdx: [TrashKey: Int]
        var itemResults: Results<RItem>?
        var itemsToken: NotificationToken?
        var collectionResults: Results<RCollection>?
        var collectionsToken: NotificationToken?

        static var empty: Snapshot {
            return Snapshot(sortedKeys: [], keyToIdx: [:])
        }

        var count: Int {
            return sortedKeys.count
        }

        func key(for index: Int) -> TrashKey? {
            guard index < sortedKeys.count else { return nil }
            return sortedKeys[index]
        }

        func object(for key: TrashKey) -> TrashObject? {
            guard let idx = keyToIdx[key] else { return nil }
            switch key.type {
            case .item:
                guard idx < (itemResults?.count ?? 0) else { return nil }
                return itemResults?[idx]

            case .collection:
                guard idx < (collectionResults?.count ?? 0) else { return nil }
                return collectionResults?[idx]
            }
        }
        
        func updated(sortedKeys: [TrashKey], keyToIdx: [TrashKey: Int], items: Results<RItem>) -> Snapshot {
            return Snapshot(sortedKeys: sortedKeys, keyToIdx: keyToIdx, itemResults: items, itemsToken: itemsToken, collectionResults: collectionResults, collectionsToken: collectionsToken)
        }

        func updated(sortedKeys: [TrashKey], keyToIdx: [TrashKey: Int], collections: Results<RCollection>) -> Snapshot {
            return Snapshot(sortedKeys: sortedKeys, keyToIdx: keyToIdx, itemResults: itemResults, itemsToken: itemsToken, collectionResults: collections, collectionsToken: collectionsToken)
        }
    }

    struct ItemData {
        let title: NSAttributedString?
        let accessory: ItemAccessory?
    }

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
        static let openItems = Changes(rawValue: 1 << 8)
    }

    enum Error: Swift.Error {
        case dataLoading
    }

    var library: Library
    var libraryToken: NotificationToken?
    var snapshot: Snapshot
    // Cache of item data (accessory, title) so that they don't need to be re-fetched in tableView.
    var itemDataCache: [TrashKey: ItemData]
    var updateItemKey: TrashKey?
    var sortType: ItemsSortType
    var searchTerm: String?
    var filters: [ItemsFilter]
    var isEditing: Bool
    var selectedItems: Set<TrashKey>
    var attachmentToOpen: String?
    var downloadBatchData: ItemsState.DownloadBatchData?
    var changes: Changes
    var error: ItemsError?
    var titleFont: UIFont {
        return UIFont.preferredFont(for: .headline, weight: .regular)
    }
    var openItemsCount: Int

    init(libraryId: LibraryIdentifier, sortType: ItemsSortType, searchTerm: String?, filters: [ItemsFilter], downloadBatchData: ItemsState.DownloadBatchData?, openItemsCount: Int) {
        snapshot = .empty
        itemDataCache = [:]
        self.sortType = sortType
        self.filters = filters
        self.searchTerm = searchTerm
        isEditing = false
        changes = []
        selectedItems = []
        self.downloadBatchData = downloadBatchData
        self.openItemsCount = openItemsCount

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
