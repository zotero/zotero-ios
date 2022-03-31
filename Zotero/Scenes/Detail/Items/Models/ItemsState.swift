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
        static let filters = Changes(rawValue: 1 << 5)
        static let webViewCleanup = Changes(rawValue: 1 << 6)
        static let batchData = Changes(rawValue: 1 << 7)
    }

    enum Filter {
        case downloadedFiles
    }

    struct DownloadBatchData: Equatable {
        let fraction: Double
        let downloaded: Int
        let total: Int

        init?(progress: Progress, remaining: Int, total: Int) {
            guard total > 1 else { return nil }
            self.fraction = progress.fractionCompleted
            self.downloaded = total - remaining
            self.total = total
        }
    }

    let collection: Collection
    let library: Library

    var sortType: ItemsSortType
    var searchTerm: String?
    var results: Results<RItem>?
    var filters: [Filter]
    // Keys for all results are stored so that when a deletion comes in it can be determined which keys were deleted and we can remove them from `selectedItems`
    var keys: [String]
    // Cache of item accessories (attachment, doi, url) so that they don't need to be re-fetched in tableView. The key is key of parent item, or item if it's a standalone attachment.
    var itemAccessories: [String: ItemAccessory]
    var selectedItems: Set<String>
    var isEditing: Bool
    var changes: Changes
    var error: ItemsError?
    var itemKeyToDuplicate: String?
    // Used to indicate which row should update it's attachment view. The update is done directly to cell instead of tableView reload.
    var updateItemKey: String?
    var processingBibliography: Bool
    var bibliographyError: Error?
    var attachmentToOpen: String?
    var downloadBatchData: DownloadBatchData?

    init(collection: Collection, library: Library, sortType: ItemsSortType, searchTerm: String?, error: ItemsError?) {
        self.collection = collection
        self.library = library
        self.filters = []
        self.keys = []
        self.itemAccessories = [:]
        self.error = error
        self.isEditing = false
        self.selectedItems = []
        self.changes = []
        self.sortType = sortType
        self.searchTerm = searchTerm
        self.processingBibliography = false
    }

    mutating func cleanup() {
        self.error = nil
        self.changes = []
        self.itemKeyToDuplicate = nil
        self.updateItemKey = nil
        self.bibliographyError = nil
    }
}
