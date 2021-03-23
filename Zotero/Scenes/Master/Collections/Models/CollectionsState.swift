//
//  CollectionsState.swift
//  Zotero
//
//  Created by Michal Rentka on 24/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

typealias CollectionStateEditingData = (key: String?, name: String, parent: Collection?)

struct CollectionsState: ViewModelState {
    struct Changes: OptionSet {
        typealias RawValue = UInt8

        let rawValue: UInt8

        static let results = Changes(rawValue: 1 << 0)
        static let selection = Changes(rawValue: 1 << 1)
        static let allItemCount = Changes(rawValue: 1 << 2)
        static let trashItemCount = Changes(rawValue: 1 << 2)
    }

    enum EditingType {
        case add
        case addSubcollection(Collection)
        case edit(Collection)
    }

    let libraryId: LibraryIdentifier

    var library: Library
    var selectedCollection: CollectionIdentifier
    var collections: [Collection]
    var editingData: CollectionStateEditingData?
    var changes: Changes
    var collectionsToken: NotificationToken?
    var searchesToken: NotificationToken?
    var itemsToken: NotificationToken?
    var trashToken: NotificationToken?
    var error: CollectionsError?
    // Used to filter out unnecessary Realm observed notification when collapsing collections.
    var collapsedKeys: [String]

    init(libraryId: LibraryIdentifier, selectedCollectionId: CollectionIdentifier) {
        self.libraryId = libraryId
        self.library = Library(identifier: .custom(.myLibrary), name: "", metadataEditable: false, filesEditable: false)
        self.selectedCollection = selectedCollectionId
        self.collections = []
        self.changes = []
        self.collapsedKeys = []
        self.error = nil
    }

    mutating func cleanup() {
        self.error = nil
        self.editingData = nil
        self.changes = []
    }
}
