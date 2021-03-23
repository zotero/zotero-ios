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

        case .select(let collectionId):
            self.update(viewModel: viewModel) { state in
                state.selectedCollection = collectionId
                state.changes.insert(.selection)
            }

        case .loadData:
            self.loadData(in: viewModel)

        case .toggleCollapsed(let collection):
            self.toggleCollapsed(for: collection, in: viewModel)
        }
    }

    private func toggleCollapsed(for collection: Collection, in viewModel: ViewModel<CollectionsActionHandler>) {
        guard let index = viewModel.state.collections.firstIndex(of: collection),
              let key = collection.identifier.key else { return }

        let collapsed = !collection.collapsed
        let libraryId = viewModel.state.library.identifier
        self.update(viewModel: viewModel) { state in
            self.set(collapsed: collapsed, startIndex: index, in: &state)
        }

        self.queue.async {
            do {
                // Since this request has to be performed in background (otherwise the main queue freezes due to writes from multiple threads during sync),
                // we can't pass `NotificationToken` to ignore next notification. So we store key of collapsed collection which will be updated and this updated will be filtered out in observation.
                let request = SetCollectionCollapsedDbRequest(collapsed: collapsed, key: key, libraryId: libraryId, ignoreNotificationTokens: nil)
                try self.dbStorage.createCoordinator().perform(request: request)
            } catch let error {
                DDLogError("CollectionsActionHandler: can't change collapsed - \(error)")
            }
        }
    }

    private func set(collapsed: Bool, startIndex index: Int, in state: inout CollectionsState) {
        // Set `collapsed` flag for collection. Toggled collection is always visible.
        state.collections[index].collapsed = collapsed
        state.collections[index].visible = true

        let collection = state.collections[index]

        if let key = collection.identifier.key {
            state.collapsedKeys.append(key)
        }
        state.changes.insert(.results)

        var ignoreLevel: Int?

        // Find collections which should be shown/hidden
        for idx in ((index + 1)..<state.collections.count) {
            let _collection = state.collections[idx]

            if collection.level >= _collection.level {
                break
            }

            if collapsed {
                // Select collapsed cell if selection is among collapsed children
                if _collection.identifier == state.selectedCollection {
                    state.selectedCollection = collection.identifier
                    state.changes.insert(.selection)
                }
                // Hide all children
                state.collections[idx].visible = false
            } else {
                if let level = ignoreLevel {
                    // If parent was collapsed, don't show children
                    if _collection.level >= level {
                        continue
                    } else {
                        ignoreLevel = nil
                    }
                }
                // Show all children which are not collapsed
                state.collections[idx].visible = true
                if _collection.collapsed {
                    // Don't show children of collapsed collection
                    ignoreLevel = _collection.level + 1
                }
            }
        }
    }

    private func loadData(in viewModel: ViewModel<CollectionsActionHandler>) {
        let libraryId = viewModel.state.libraryId

        do {
            let coordinator = try self.dbStorage.createCoordinator()
            let library = try coordinator.perform(request: ReadLibraryDbRequest(libraryId: libraryId))
            let collections = try coordinator.perform(request: ReadCollectionsDbRequest(libraryId: libraryId))
            let searches = try coordinator.perform(request: ReadSearchesDbRequest(libraryId: libraryId))
            let allItems = try coordinator.perform(request: ReadItemsDbRequest(type: .all, libraryId: libraryId))
//            let publicationItemsCount = try coordinator.perform(request: ReadItemsDbRequest(type: .publications, libraryId: libraryId)).count
            let trashItems = try coordinator.perform(request: ReadItemsDbRequest(type: .trash, libraryId: libraryId))

            var allCollections: [Collection] = [Collection(custom: .all, itemCount: allItems.count),
               //                                 Collection(custom: .publications, itemCount: publicationItemsCount),
                                                Collection(custom: .trash, itemCount: trashItems.count)]
            allCollections.insert(contentsOf: CollectionTreeBuilder.collections(from: collections, libraryId: libraryId) +
                                              CollectionTreeBuilder.collections(from: searches),
                                  at: 1)

            let collectionsToken = collections.observe({ [weak viewModel] changes in
                guard let viewModel = viewModel else { return }
                switch changes {
                case .update(let objects, let deletions, let insertions, let modifications):
                    if deletions.isEmpty && insertions.isEmpty && modifications.count == 1, let key = modifications.first.flatMap({ objects[$0].key }), viewModel.state.collapsedKeys.contains(key) {
                        // See `toggleCollapsed(for:in:)` why this needs to be filtered out.
                        self.update(viewModel: viewModel) { state in
                            if let index = state.collapsedKeys.firstIndex(of: key) {
                                state.collapsedKeys.remove(at: index)
                            }
                        }
                        return
                    }
                    let collections = CollectionTreeBuilder.collections(from: objects, libraryId: libraryId)
                    self.update(collections: collections, in: viewModel)
                case .initial: break
                case .error: break
                }
            })

            let searchesToken = searches.observe({ [weak viewModel] changes in
                guard let viewModel = viewModel else { return }
                switch changes {
                case .update(let objects, _, _, _):
                    let collections = CollectionTreeBuilder.collections(from: objects)
                    self.update(collections: collections, in: viewModel)
                case .initial: break
                case .error: break
                }
            })

            let itemsToken = allItems.observe({ [weak viewModel] changes in
                guard let viewModel = viewModel else { return }
                switch changes {
                case .update(let objects, _, _, _):
                    self.update(allItemsCount: objects.count, in: viewModel)
                case .initial: break
                case .error: break
                }
            })

            let trashToken = trashItems.observe({ [weak viewModel] changes in
                guard let viewModel = viewModel else { return }
                switch changes {
                case .update(let objects, _, _, _):
                    self.update(trashItemCount: objects.count, in: viewModel)
                case .initial: break
                case .error: break
                }
            })

            self.update(viewModel: viewModel) { state in
                state.collections = allCollections
                state.library = library
                state.collectionsToken = collectionsToken
                state.searchesToken = searchesToken
                state.itemsToken = itemsToken
                state.trashToken = trashToken
            }
        } catch let error {
            DDLogError("CollectionsActionHandlers: can't load data - \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .dataLoading
            }
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
        var parent: Collection?

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
            key = collection.identifier.key
            name = collection.name

            if let parentKey = collection.parentKey, let coordinator = try? self.dbStorage.createCoordinator() {
                let request = ReadCollectionDbRequest(libraryId: viewModel.state.library.identifier, key: parentKey)
                let rCollection = try? coordinator.perform(request: request)
                parent = rCollection.flatMap { Collection(object: $0, level: 0, visible: true, hasChildren: true, parentKey: $0.parentKey, itemCount: 0) }
            }
        }

        self.update(viewModel: viewModel) { state in
            state.editingData = (key, name, parent)
        }
    }

    private func update(allItemsCount: Int, in viewModel: ViewModel<CollectionsActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.collections[0].itemCount = allItemsCount
            state.changes = .allItemCount
        }
    }

    private func update(trashItemCount: Int, in viewModel: ViewModel<CollectionsActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.collections[state.collections.count - 1] = Collection(custom: .trash, itemCount: trashItemCount)
            state.changes = .trashItemCount
        }
    }

    private func update(collections: [Collection], in viewModel: ViewModel<CollectionsActionHandler>) {
        guard !collections.isEmpty else { return }

        var original = viewModel.state.collections
        var selectedId = viewModel.state.selectedCollection

        self.update(original: &original, with: collections)
        if !original.contains(where: { $0.identifier == selectedId }) {
            selectedId = original.first?.identifier ?? .custom(.all)
        }

        self.update(viewModel: viewModel) { state in
            state.collections = original
            state.changes.insert(.results)
            if selectedId != state.selectedCollection {
                state.changes.insert(.selection)
                state.selectedCollection = selectedId
            }
        }
    }

    /// Updates existing collections of the same type. If no collection of given type exists yet, collections are inserted
    /// into appropriate position based on CollectionType.
    /// - parameter original: Original collections. 
    /// - parameter collections: collections to be inserted/updated.
    private func update(original: inout [Collection], with collections: [Collection]) {
        guard let identifier = collections.first?.identifier else { return }

        if self.replaceCollections(with: identifier, with: collections, original: &original) { return }

        switch identifier {
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
    private func replaceCollections(with identifier: CollectionIdentifier, with collections: [Collection], original: inout [Collection]) -> Bool {
        var startIndex = -1
        var endIndex = -1

        for (idx, collection) in original.enumerated() {
            if startIndex == -1 {
                if collection.identifier.isSameType(as: identifier) {
                    startIndex = idx
                }
            } else if endIndex == -1 {
                if !collection.identifier.isSameType(as: identifier) {
                    endIndex = idx
                    break
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
