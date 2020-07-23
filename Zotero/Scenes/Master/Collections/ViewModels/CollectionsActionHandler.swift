//
//  CollectionsActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 24/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
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
                // Finish search when item is selected
                self.removeCollectionsFilter(in: &state)
                state.changes.insert(.selection)
            }

        case .updateCollections(let collections):
            self.update(collections: collections.map({ SearchableCollection(isActive: true, collection: $0) }), in: viewModel)

        case .loadData:
            self.loadData(in: viewModel)

        case .search(let term):
            self.search(for: term, in: viewModel)
        }
    }

    private func search(for term: String, in viewModel: ViewModel<CollectionsActionHandler>) {
        if term.isEmpty {
            guard viewModel.state.snapshot != nil else { return }
            self.update(viewModel: viewModel) { state in
                self.removeCollectionsFilter(in: &state)
            }
        } else {
            self.filterCollections(with: term, in: viewModel)
        }
    }

    private func filterCollections(with text: String, in viewModel: ViewModel<CollectionsActionHandler>) {
        self.update(viewModel: viewModel) { state in
            if state.snapshot == nil {
                state.snapshot = state.collections
            }
            state.collections = self.filter(collections: (state.snapshot ?? state.collections), with: text)
            state.changes = .results
        }
    }

    private func filter(collections: [SearchableCollection], with text: String) -> [SearchableCollection] {
        var filtered: [SearchableCollection] = []

        // Go through all collections, find results and insert their parents.
        for (i, searchable) in collections.enumerated() {
            guard searchable.collection.name.localizedCaseInsensitiveContains(text) else { continue }

            // Check whether we need to look for parents of this collection. We need to look for parents when the level > 0
            // (otherwise there are no parents) and previously inserted collection doesn't have the same parent as this one
            // (otherwise we already have all parents from previous collection).
            let shouldLookForParents = searchable.collection.level > 0 && filtered.last?.collection.parentKey != searchable.collection.parentKey

            // Collection contains text, append.
            filtered.append(searchable.isActive(true))

            guard shouldLookForParents else { continue }

            // Track back to search for all parents
            let insertionIndex = filtered.count - 1
            var lastLevel = searchable.collection.level

            for j in (0..<i).reversed() {
                let parent = collections[j]

                // If level changed, we found a new parent
                guard parent.collection.level < lastLevel else { continue }

                // Parent is already in filtered array, stop searching for parents
                if filtered.reversed().firstIndex(where: { $0.collection == parent.collection }) != nil {
                    break
                }

                filtered.insert(parent.isActive(false), at: insertionIndex)

                // If this parent is already on root level, stop searching for parents
                if parent.collection.level == 0 {
                    break
                }

                lastLevel = parent.collection.level
            }
        }

        return filtered
    }

    private func removeCollectionsFilter(in state: inout State) {
        guard let snapshot = state.snapshot else { return }
        state.collections = snapshot
        state.snapshot = nil
        state.changes = .results
    }

    private func loadData(in viewModel: ViewModel<CollectionsActionHandler>) {
        let libraryId = viewModel.state.library.identifier

        do {
            let coordinator = try self.dbStorage.createCoordinator()
            let collections = try coordinator.perform(request: ReadCollectionsDbRequest(libraryId: libraryId))
            let searches = try coordinator.perform(request: ReadSearchesDbRequest(libraryId: libraryId))
            let allItems = try coordinator.perform(request: ReadItemsDbRequest(type: .all, libraryId: libraryId))
//            let publicationItemsCount = try coordinator.perform(request: ReadItemsDbRequest(type: .publications, libraryId: libraryId)).count
            let trashItemsCount = try coordinator.perform(request: ReadItemsDbRequest(type: .trash, libraryId: libraryId)).count

            var allCollections: [Collection] = [Collection(custom: .all, itemCount: allItems.count),
               //                                 Collection(custom: .publications, itemCount: publicationItemsCount),
                                                Collection(custom: .trash, itemCount: trashItemsCount)]
            allCollections.insert(contentsOf: CollectionTreeBuilder.collections(from: collections) +
                                              CollectionTreeBuilder.collections(from: searches),
                                  at: 1)

            let collectionsToken = collections.observe({ [weak viewModel] changes in
                guard let viewModel = viewModel else { return }
                switch changes {
                case .update(let objects, _, _, _):
                    let collections = CollectionTreeBuilder.collections(from: objects).map({ SearchableCollection(isActive: true, collection: $0) })
                    self.update(collections: collections, in: viewModel)
                case .initial: break
                case .error: break
                }
            })

            let searchesToken = searches.observe({ [weak viewModel] changes in
                guard let viewModel = viewModel else { return }
                switch changes {
                case .update(let objects, _, _, _):
                    let collections = CollectionTreeBuilder.collections(from: objects).map({ SearchableCollection(isActive: true, collection: $0) })
                    self.update(collections: collections, in: viewModel)
                case .initial: break
                case .error: break
                }
            })

            let itemsToken = allItems.observe { [weak viewModel] changes in
                guard let viewModel = viewModel else { return }
                switch changes {
                case .update(let objects, let deletions, let insertions, _):
                    // If we show item counts for all collections, we need to track all changes (insertion, deletion, collection change).
                    // Otherwise we need to track only insertions and deletions for all items.
                    if Defaults.shared.showCollectionItemCount || (!insertions.isEmpty || !deletions.isEmpty) {
                        self.updateItemCounts(in: viewModel, allItemCount: objects.count)
                    }
                case .initial: break
                case .error: break
                }
            }

            self.update(viewModel: viewModel) { state in
                state.collections = allCollections.map({ SearchableCollection(isActive: true, collection: $0) })
                if !allCollections.isEmpty {
                    state.selectedCollection = allCollections[0]
                }
                state.collectionsToken = collectionsToken
                state.searchesToken = searchesToken
                state.itemsToken = itemsToken
            }
        } catch let error {
            DDLogError("CollectionsActionHandlers: can't load data - \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .dataLoading
            }
        }
    }

    private func updateItemCounts(in viewModel: ViewModel<CollectionsActionHandler>, allItemCount: Int) {
        if Defaults.shared.showCollectionItemCount {
            self.reloadCounts(in: viewModel, allItemCount: allItemCount)
            return
        }

        self.update(viewModel: viewModel) { state in
            if var snapshot = state.snapshot {
                // If the user is searching, update the snapshot and don't update UI
                self.updateAllItemCount(to: allItemCount, in: &snapshot)
                state.snapshot = snapshot
            } else {
                // If the user is not searching, update collections and reload the UI
                if self.updateAllItemCount(to: allItemCount, in: &state.collections) {
                    state.changes.insert(.itemCount)
                }
            }
        }
    }

    @discardableResult
    private func updateAllItemCount(to count: Int, in collections: inout [SearchableCollection]) -> Bool {
        if let index = collections.firstIndex(where: { $0.collection.isCustom(type: .all) }) {
            collections[index].collection.itemCount = count
            return true
        }
        return false
    }

    private func reloadCounts(in viewModel: ViewModel<CollectionsActionHandler>, allItemCount: Int) {
        let libraryId = viewModel.state.library.identifier
        var allCollections = viewModel.state.snapshot ?? viewModel.state.collections

        do {
            let coordinator = try self.dbStorage.createCoordinator()

            for (index, searchable) in allCollections.enumerated() {
                let count: Int
                switch searchable.collection.type {
                case .collection:
                    count = try coordinator.perform(request: ReadItemsDbRequest(type: .collection(searchable.collection.key,
                                                                                                  searchable.collection.name),
                                                                                libraryId: libraryId)).count
                case .search:
                    count = try coordinator.perform(request: ReadItemsDbRequest(type: .search(searchable.collection.key,
                                                                                              searchable.collection.name),
                                                                                libraryId: libraryId)).count
                case .custom(let type):
                    switch type {
                    case .all:
                        count = allItemCount
                    case .publications:
                        count = try coordinator.perform(request: ReadItemsDbRequest(type: .publications, libraryId: libraryId)).count
                    case .trash:
                        count = try coordinator.perform(request: ReadItemsDbRequest(type: .trash, libraryId: libraryId)).count
                    }
                }
                allCollections[index].collection.itemCount = count
            }

            self.update(viewModel: viewModel) { state in
                if state.snapshot != nil {
                    // If the user is searching, just update the snapshot and don't reload
                    state.snapshot = allCollections
                } else {
                    // If the user is not searching, update all collections and reload data
                    state.collections = allCollections
                    state.changes.insert(.itemCount)
                }
            }
        } catch let error {
            DDLogError("CollectionsActionHandlers: can't load counts - \(error)")
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

    private func delete<Obj: DeletableObject&Updatable>(object: Obj.Type,
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
            parent = rCollection?.parent.flatMap { Collection(object: $0, level: 0, parentKey: $0.parent?.key) }
        }

        self.update(viewModel: viewModel) { state in
            state.editingData = (key, name, parent)
        }
    }

    private func update(collections: [SearchableCollection], in viewModel: ViewModel<CollectionsActionHandler>) {
        self.update(viewModel: viewModel) { state in
            if var snapshot = state.snapshot {
                // If the user is searching, update snapshot with new collections and don't reload UI
                self.update(collections: collections, original: &snapshot)
                state.snapshot = snapshot
            } else {
                // If user is not searching, update original collections with new collections and reload UI
                self.update(collections: collections, original: &state.collections)
                state.changes.insert(.results)
            }
        }
    }

    /// Updates existing collections of the same type. If no collection of given type exists yet, collections are inserted
    /// into appropriate position based on CollectionType.
    /// - parameter collections: collections to be inserted/updated.
    /// - parameter original: Original collections.
    private func update(collections: [SearchableCollection], original: inout [SearchableCollection]) {
        guard !collections.isEmpty, let type = collections.first?.collection.type else { return }

        if self.replaceCollections(of: type, with: collections, original: &original) { return }

        switch type {
        case .collection:
            // Insert new "collection" collections after "all" collection
            original.insert(contentsOf: collections, at: 1)
        case .search:
            // Insert new "search" collections before "publications" collection, after "collection" collections
            original.insert(contentsOf: collections, at: original.count - 2)
        case .custom: return // don't update custom collections
        }
    }

    /// Replaces existing collections of the same type with new collections.
    /// - parameter type: Type of collections.
    /// - parameter collections: New collections to replace existing ones.
    /// - parameter original: Original collections.
    /// - returns: False if there are no collections to replace, true otherwise.
    private func replaceCollections(of type: Collection.CollectionType, with collections: [SearchableCollection],
                                    original: inout [SearchableCollection]) -> Bool {
        var startIndex = -1
        var endIndex = -1

        for data in original.enumerated() {
            if startIndex == -1 {
                if data.element.collection.type == type {
                    startIndex = data.offset
                }
            } else if endIndex == -1 {
                if data.element.collection.type != type {
                    endIndex = data.offset
                }
            }
        }

        if startIndex == -1 { return false } // no object of given type found

        if endIndex == -1 { // last cell was of the same type, so endIndex is at the end
            endIndex = original.count
        }

        // Replace old collections of this type with new collections
        original.remove(atOffsets: IndexSet(integersIn: startIndex..<endIndex))
        original.insert(contentsOf: collections, at: startIndex)

        return true
    }
}
