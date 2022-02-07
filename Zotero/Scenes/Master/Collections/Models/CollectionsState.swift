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
    var selectedCollectionId: CollectionIdentifier
    var collections: [CollectionIdentifier: Collection]
    var rootCollections: [CollectionIdentifier]
    var childCollections: [CollectionIdentifier: [CollectionIdentifier]]
    var collapsedState: [CollectionIdentifier: Bool]
    var editingData: CollectionStateEditingData?
    var changes: Changes
    var collectionsToken: NotificationToken?
    var searchesToken: NotificationToken?
    var itemsToken: NotificationToken?
    var trashToken: NotificationToken?
    var error: CollectionsError?
    // Used to filter out unnecessary Realm observed notification when collapsing collections.
//    var collapsedKeys: [String]
    // Used to filter out unnecessary Realm observed notification when collapsing all collections.
//    var collectionsToggledCount: Int?
    // Used when user wants to create bibliography from whole collection.
    var itemKeysForBibliography: Swift.Result<Set<String>, Error>?

//    var hasExpandableCollection: Bool {
//        return self.collections.contains(where: { $0.level > 0 })
//    }
//
//    var areAllExpanded: Bool {
//        return !self.collections.contains(where: { !$0.visible })
//    }

    init(libraryId: LibraryIdentifier, selectedCollectionId: CollectionIdentifier) {
        self.libraryId = libraryId
        self.library = Library(identifier: .custom(.myLibrary), name: "", metadataEditable: false, filesEditable: false)
        self.selectedCollectionId = selectedCollectionId
        self.collections = [:]
        self.rootCollections = []
        self.childCollections = [:]
        self.collapsedState = [:]
        self.changes = []
//        self.collapsedKeys = []
    }

    mutating func cleanup() {
        self.error = nil
        self.editingData = nil
        self.changes = []
        self.itemKeysForBibliography = nil
    }
}
