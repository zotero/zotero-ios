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
        static let batchData = Changes(rawValue: 1 << 6)
        static let library = Changes(rawValue: 1 << 7)
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
        
        init?(progress: Progress?, remaining: Int, total: Int) {
            guard let progress, total > 0 else { return nil }
            self.fraction = progress.fractionCompleted
            self.downloaded = total - remaining
            self.total = total
        }
        
        init?(batchData: (progress: Progress?, remainingCount: Int, totalCount: Int)) {
            self.init(progress: batchData.progress, remaining: batchData.remainingCount, total: batchData.totalCount)
        }
        
        static func + (lhs: Self, rhs: Self) -> Self {
            let fraction = (lhs.fraction + rhs.fraction) / 2.0
            let downloaded = lhs.downloaded + rhs.downloaded
            let total = lhs.total + rhs.total
            return .init(fraction: fraction, downloaded: downloaded, total: total)
        }
        
        static func combineDownloadBatchData(_ array: [Self?]) -> Self? {
            let validArray = array.compactMap { $0 }
            guard let firstData = validArray.first else { return nil }
            guard validArray.count > 1 else { return firstData }
            return validArray[1..<validArray.endIndex].reduce(firstData) { $0 + $1 }
        }
    }
    
    struct IdentifierLookupBatchData: Equatable {
        static let zero: Self = .init(saved: 0, total: 0)
        
        let saved: Int
        let total: Int
        
        init(saved: Int, total: Int) {
            self.saved = saved
            self.total = total
        }
        
        init(batchData: (savedCount: Int, failedCount: Int, totalCount: Int)) {
            self.init(saved: batchData.savedCount, total: batchData.totalCount - batchData.failedCount)
        }
        
        var isFinished: Bool {
            saved == total
        }
    }

    let collection: Collection
    let libraryId: LibraryIdentifier

    var library: Library
    var libraryToken: NotificationToken?
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
    var attachmentToOpen: String?
    var downloadBatchData: DownloadBatchData?
    var remoteDownloadBatchData: DownloadBatchData?
    var identifierLookupBatchData: IdentifierLookupBatchData
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

    init(
        collection: Collection,
        libraryId: LibraryIdentifier,
        sortType: ItemsSortType,
        searchTerm: String?,
        filters: [ItemsFilter],
        downloadBatchData: DownloadBatchData?,
        remoteDownloadBatchData: DownloadBatchData?,
        identifierLookupBatchData: IdentifierLookupBatchData,
        error: ItemsError?
    ) {
        self.collection = collection
        self.libraryId = libraryId
        self.filters = []
        self.keys = []
        self.itemAccessories = [:]
        self.error = error
        self.isEditing = false
        self.selectedItems = []
        self.changes = []
        self.sortType = sortType
        self.filters = filters
        self.downloadBatchData = downloadBatchData
        self.remoteDownloadBatchData = remoteDownloadBatchData
        self.identifierLookupBatchData = identifierLookupBatchData
        self.searchTerm = searchTerm
        self.itemTitles = [:]

        switch libraryId {
        case .custom:
            library = Library(identifier: libraryId, name: L10n.Libraries.myLibrary, metadataEditable: false, filesEditable: false)

        case .group(let groupId):
            library = Library(identifier: libraryId, name: L10n.unknown, metadataEditable: false, filesEditable: false)
        }
    }

    mutating func cleanup() {
        self.error = nil
        self.changes = []
        self.itemKeyToDuplicate = nil
        self.updateItemKey = nil
    }
}
