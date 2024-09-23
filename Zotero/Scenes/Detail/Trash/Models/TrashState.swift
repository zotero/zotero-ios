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
    var objects: OrderedDictionary<TrashKey, TrashObject>
    var filters: [ItemsFilter]
    var isEditing: Bool
    var selectedItems: Set<TrashKey>
    var changes: Changes
    var error: ItemsError?
    var titleFont: UIFont {
        return UIFont.preferredFont(for: .headline, weight: .regular)
    }

    init(libraryId: LibraryIdentifier) {
        objects = [:]
        filters = []
        isEditing = false
        changes = []
        selectedItems = []

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
