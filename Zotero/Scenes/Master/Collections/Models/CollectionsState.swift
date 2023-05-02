//
//  CollectionsState.swift
//  Zotero
//
//  Created by Michal Rentka on 24/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

typealias CollectionStateEditingData = (key: String?, name: String, parent: Collection?, shouldCollapse: Bool)

struct CollectionsState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let results = Changes(rawValue: 1 << 0)
        static let selection = Changes(rawValue: 1 << 1)
        static let allItemCount = Changes(rawValue: 1 << 2)
        static let trashItemCount = Changes(rawValue: 1 << 3)
        static let unfiledItemCount = Changes(rawValue: 1 << 4)
        static let collapsedState = Changes(rawValue: 1 << 5)
    }

    enum EditingType {
        case add
        case addSubcollection(Collection)
        case edit(Collection)
    }

    let libraryId: LibraryIdentifier

    var library: Library
    var collectionTree: CollectionTree
    var selectedCollectionId: CollectionIdentifier
    var editingData: CollectionStateEditingData?
    var changes: Changes
    var collectionsToken: NotificationToken?
    var searchesToken: NotificationToken?
    var itemsToken: NotificationToken?
    var unfiledToken: NotificationToken?
    var trashToken: NotificationToken?
    var error: CollectionsError?
    // Used when user wants to create bibliography from whole collection.
    var itemKeysForBibliography: Swift.Result<Set<String>, Error>?

    init(libraryId: LibraryIdentifier, selectedCollectionId: CollectionIdentifier) {
        self.libraryId = libraryId
        self.library = Library(identifier: .custom(.myLibrary), name: "", metadataEditable: false, filesEditable: false)
        self.selectedCollectionId = selectedCollectionId
        self.changes = []
        self.collectionTree = CollectionTree(nodes: [], collections: [:], collapsed: [:])
    }

    mutating func cleanup() {
        self.error = nil
        self.editingData = nil
        self.changes = []
        self.itemKeysForBibliography = nil
    }
}
