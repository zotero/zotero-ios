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

        static var empty: Snapshot {
            return Snapshot(sortedKeys: [], keyToIdx: [:])
        }

        var count: Int {
            return sortedKeys.count
        }
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
    }

    enum Error: Swift.Error {
        case dataLoading
    }

    var library: Library
    var libraryToken: NotificationToken?
    var itemResults: Results<RItem>?
    var itemsToken: NotificationToken?
    var collectionResults: Results<RCollection>?
    var collectionsToken: NotificationToken?
    var snapshot: Snapshot
    // Cache of item accessories (attachment, doi, url) so that they don't need to be re-fetched in tableView. The key is key of parent item, or item if it's a standalone attachment.
    var itemAccessories: [TrashKey: ItemAccessory]
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

    init(libraryId: LibraryIdentifier, sortType: ItemsSortType, searchTerm: String?, filters: [ItemsFilter], downloadBatchData: ItemsState.DownloadBatchData?) {
        snapshot = .empty
        itemAccessories = [:]
        self.sortType = sortType
        self.filters = filters
        self.searchTerm = searchTerm
        isEditing = false
        changes = []
        selectedItems = []
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
    }
}
