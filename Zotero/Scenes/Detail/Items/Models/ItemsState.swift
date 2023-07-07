//
//  ItemsState.swift
//  Zotero
//
//  Created by Michal Rentka on 21/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

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

    struct DownloadBatchData: Equatable {
        let fraction: Double
        let downloaded: Int
        let total: Int

        init(fraction: Double, downloaded: Int, total: Int) {
            self.fraction = fraction
            self.downloaded = downloaded
            self.total = total
        }
        
        init?(progress: Progress, remaining: Int, total: Int) {
            guard total > 1 else { return nil }
            self.fraction = progress.fractionCompleted
            self.downloaded = total - remaining
            self.total = total
        }
        
        static func + (lhs: DownloadBatchData, rhs: DownloadBatchData) -> DownloadBatchData {
            let fraction = (lhs.fraction + rhs.fraction) / 2.0
            let downloaded = lhs.downloaded + rhs.downloaded
            let total = lhs.total + rhs.total
            return .init(fraction: fraction, downloaded: downloaded, total: total)
        }
    }

    let collection: Collection
    let library: Library

    var sortType: ItemsSortType
    var searchTerm: String?
    var results: Results<RItem>?
    var filters: [ItemsFilter]
    // Keys for all results are stored so that when a deletion comes in it can be determined which keys were deleted and we can remove them from `selectedItems`
    var keys: [String]
    // Cache of item accessories (attachment, doi, url) so that they don't need to be re-fetched in tableView. The key is key of parent item, or item if it's a standalone attachment.
    var itemAccessories: [String: ItemAccessory]
    // Cache of attributed item titles
    var itemTitles: [String: NSAttributedString]
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
    var remoteDownloadBatchData: DownloadBatchData?
    var combinedDownloadBatchData: DownloadBatchData? {
        let data = [downloadBatchData, remoteDownloadBatchData].compactMap { $0 }
        guard let firstData = data.first else { return nil }
        guard data.count > 1 else { return firstData }
        return data[1..<data.endIndex].reduce(firstData) { $0 + $1 }
    }
    var itemTitleFont: UIFont {
        return UIFont.preferredFont(for: .headline, weight: .regular)
    }

    var tagsFilter: Set<String>? {
        let tagFilter = self.filters.first(where: { filter in
            switch filter {
            case .tags: return true
            default: return false
            }
        })

        guard let tagFilter = tagFilter, case .tags(let tags) = tagFilter else { return nil }
        return tags
    }

    init(collection: Collection, library: Library, sortType: ItemsSortType, searchTerm: String?, filters: [ItemsFilter], error: ItemsError?) {
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
        self.filters = filters
        self.searchTerm = searchTerm
        self.processingBibliography = false
        self.itemTitles = [:]
    }

    mutating func cleanup() {
        self.error = nil
        self.changes = []
        self.itemKeyToDuplicate = nil
        self.updateItemKey = nil
        self.bibliographyError = nil
    }
}
