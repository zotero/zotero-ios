//
//  CollectionsActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 24/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack
import RealmSwift

struct CollectionsActionHandler: ViewModelActionHandler {
    typealias Action = CollectionsAction
    typealias State = CollectionsState

    private let queue: DispatchQueue
    private let dbStorage: DbStorage

    init(dbStorage: DbStorage) {
        self.queue = DispatchQueue.global(qos: .userInitiated)
        self.dbStorage = dbStorage
    }

    func process(action: CollectionsAction, in viewModel: ViewModel<CollectionsActionHandler>) {
        switch action {
        case .startEditing(let type):
            self.startEditing(type: type, in: viewModel)

        case .assignKeysToCollection(let fromKeys, let toKey):
            self.queue.async { [weak viewModel] in
                guard let viewModel = viewModel else { return }
                self.assignItems(keys: fromKeys, to: toKey, in: viewModel)
            }

        case .deleteCollection(let key):
            self.queue.async { [weak viewModel] in
                guard let viewModel = viewModel else { return }
                self.delete(object: RCollection.self, keys: [key], in: viewModel)
            }

        case .deleteSearch(let key):
            self.queue.async { [weak viewModel] in
                guard let viewModel = viewModel else { return }
                self.delete(object: RSearch.self, keys: [key], in: viewModel)
            }

        case .select(let collection):
            self.update(viewModel: viewModel) { state in
                state.selectedCollection = collection
                state.changes.insert(.selection)
            }

        case .updateCollections(let collections):
            self.update(collections: collections, in: viewModel)
        }
    }

    private func assignItems(keys: [String], to collectionKey: String, in viewModel: ViewModel<CollectionsActionHandler>) {
        do {
            let request = AssignItemsToCollectionsDbRequest(collectionKeys: Set([collectionKey]),
                                                            itemKeys: Set(keys),
                                                            libraryId: viewModel.state.library.identifier)
            try self.dbStorage.createCoordinator().perform(request: request)
        } catch let error {
            DDLogError("CollectionsStore: can't assign collections to items - \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .collectionAssignment
            }
        }
    }

    private func delete<Obj: DeletableObject>(object: Obj.Type,
                                              keys: [String],
                                              in viewModel: ViewModel<CollectionsActionHandler>) {
        do {
            let request = MarkObjectsAsDeletedDbRequest<Obj>(keys: keys, libraryId: viewModel.state.library.identifier)
            try self.dbStorage.createCoordinator().perform(request: request)
        } catch let error {
            DDLogError("CollectionsStore: can't delete object - \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .deletion
            }
        }
    }

    /// Loads data needed to show editing controller.
    /// - parameter type: Editing type.
    private func startEditing(type: CollectionsState.EditingType, in viewModel: ViewModel<CollectionsActionHandler>) {
        let key: String?
        let name: String
        let parent: Collection?

        switch type {
        case .add:
            key = nil
            name = ""
            parent = nil
        case .addSubcollection(let collection):
            key = nil
            name = ""
            parent = collection
        case .edit(let collection):
            let request = ReadCollectionDbRequest(libraryId: viewModel.state.library.identifier, key: collection.key)
            let rCollection = try? self.dbStorage.createCoordinator().perform(request: request)

            key = collection.key
            name = collection.name
            parent = rCollection?.parent.flatMap { Collection(object: $0, level: 0) }
        }

        self.update(viewModel: viewModel) { state in
            state.editingData = (key, name, parent)
        }
    }

    private func update(collections: [Collection], in viewModel: ViewModel<CollectionsActionHandler>) {
        self.update(viewModel: viewModel) { state in
            self.update(collections: collections, state: &state)
            state.changes.insert(.results)
        }
    }

    /// Updates existing collections of the same type. If no collection of given type exists yet, collections are inserted
    /// into appropriate position based on CollectionType.
    /// - parameter collections: collections to be inserted/updated
    private func update(collections: [Collection], state: inout CollectionsState) {
        guard !collections.isEmpty, let type = collections.first?.type else { return }

        if self.replaceCollections(of: type, with: collections, state: &state) { return }

        switch type {
        case .collection:
            // Insert new "collection" collections after "all" collection
            state.collections.insert(contentsOf: collections, at: 1)
        case .search:
            // Insert new "search" collections before "publications" collection, after "collection" collections
            state.collections.insert(contentsOf: collections, at: state.collections.count - 2)
        case .custom: return // don't update custom collections
        }
    }

    /// Replaces existing collections of the same type with new collections.
    /// - parameter type: Type of collections.
    /// - parameter collections: New collections to replace existing ones.
    /// - parameter state: Current state.
    /// - returns: False if there are no collections to replace, true otherwise.
    private func replaceCollections(of type: Collection.CollectionType, with collections: [Collection], state: inout CollectionsState) -> Bool {
        var startIndex = -1
        var endIndex = -1

        for data in state.collections.enumerated() {
            if startIndex == -1 {
                if data.element.type == type {
                    startIndex = data.offset
                }
            } else if endIndex == -1 {
                if data.element.type != type {
                    endIndex = data.offset
                }
            }
        }

        if startIndex == -1 { return false } // no object of given type found

        if endIndex == -1 { // last cell was of the same type, so endIndex is at the end
            endIndex = state.collections.count
        }

        // Replace old collections of this type with new collections
        state.collections.remove(atOffsets: IndexSet(integersIn: startIndex..<endIndex))
        state.collections.insert(contentsOf: collections, at: startIndex)

        return true
    }
}
