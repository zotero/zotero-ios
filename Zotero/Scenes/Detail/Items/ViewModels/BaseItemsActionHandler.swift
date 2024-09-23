//
//  BaseItemsActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 23.09.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift
import RealmSwift
import RxSwift

class BaseItemsActionHandler: BackgroundDbProcessingActionHandler {
    unowned let dbStorage: DbStorage
    let backgroundQueue: DispatchQueue

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
        self.backgroundQueue = DispatchQueue(label: "org.zotero.BaseItemsActionHandler.backgroundProcessing", qos: .userInitiated)
    }

    // MARK: - Filtering

    func add(filter: ItemsFilter, to filters: [ItemsFilter]) -> [ItemsFilter] {
        guard !filters.contains(filter) else { return filters }

        let modificationIndex = filters.firstIndex(where: { existing in
            switch (existing, filter) {
            // Update array inside existing `tags` filter
            case (.tags, .tags):
                return true

            default:
                return false
            }
        })

        var newFilters = filters
        if let index = modificationIndex {
            newFilters[index] = filter
        } else {
            newFilters.append(filter)
        }
        return newFilters
    }

    func remove(filter: ItemsFilter, from filters: [ItemsFilter]) -> [ItemsFilter] {
        guard let index = filters.firstIndex(of: filter) else { return filters }
        var newFilters = filters
        newFilters.remove(at: index)
        return newFilters
    }

    // MARK: - Drag & Drop

    func moveItems(from keys: Set<String>, to key: String, libraryId: LibraryIdentifier, completion: @escaping (Result<Void, ItemsError>) -> Void) {
        let request = MoveItemsToParentDbRequest(itemKeys: keys, parentKey: key, libraryId: libraryId)
        self.perform(request: request) { error in
            guard let error else { return }
            DDLogError("BaseItemsActionHandler: can't move items to parent: \(error)")
            completion(.failure(.itemMove))
        }
    }

    func add(items itemKeys: Set<String>, to collectionKeys: Set<String>, libraryId: LibraryIdentifier, completion: @escaping (Result<Void, ItemsError>) -> Void) {
        let request = AssignItemsToCollectionsDbRequest(collectionKeys: collectionKeys, itemKeys: itemKeys, libraryId: libraryId)
        self.perform(request: request) { error in
            guard let error else { return }
            DDLogError("BaseItemsActionHandler: can't assign collections to items - \(error)")
            completion(.failure(.collectionAssignment))
        }
    }

    func tagItem(key: String, libraryId: LibraryIdentifier, with names: Set<String>) {
        let request = AddTagsToItemDbRequest(key: key, libraryId: libraryId, tagNames: names)
        self.perform(request: request) { error in
            guard let error = error else { return }
            // TODO: - show error
            DDLogError("BaseItemsActionHandler: can't add tags - \(error)")
        }
    }

    // MARK: - Toolbar Actions

    func deleteItemsFromCollection(keys: Set<String>, collectionId: CollectionIdentifier, libraryId: LibraryIdentifier, completion: @escaping (Result<Void, ItemsError>) -> Void) {
        guard let key = collectionId.key else { return }
        let request = DeleteItemsFromCollectionDbRequest(collectionKey: key, itemKeys: keys, libraryId: libraryId)
        self.perform(request: request) { error in
            guard let error else { return }
            DDLogError("BaseItemsActionHandler: can't delete items - \(error)")
            completion(.failure(.deletionFromCollection))
        }
    }

    func set(trashed: Bool, to keys: Set<String>, libraryId: LibraryIdentifier, completion: @escaping (Result<Void, ItemsError>) -> Void) {
        let request = MarkItemsAsTrashedDbRequest(keys: Array(keys), libraryId: libraryId, trashed: trashed)
        self.perform(request: request) { error in
            guard let error else { return }
            DDLogError("BaseItemsActionHandler: can't trash items - \(error)")
            completion(.failure(.deletion))
        }
    }
}
