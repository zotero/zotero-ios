//
//  CollectionsPickerActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct CollectionsPickerActionHandler: ViewModelActionHandler {
    typealias Action = CollectionsPickerAction
    typealias State = CollectionsPickerState

    private unowned let dbStorage: DbStorage

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
    }

    func process(action: CollectionsPickerAction, in viewModel: ViewModel<CollectionsPickerActionHandler>) {
        switch action {
        case .loadData:
            self.loadData(in: viewModel)

        case .select(let collection):
            guard let key = collection.identifier.key else { return }
            self.update(viewModel: viewModel) { state in
                if !state.selected.contains(key) {
                    state.selected.insert(key)
                    state.changes = .selection
                }
            }

        case .deselect(let collection):
            guard let key = collection.identifier.key else { return }
            self.update(viewModel: viewModel) { state in
                if state.selected.contains(key) {
                    state.selected.remove(key)
                    state.changes = .selection
                }
            }

        case .setError(let error):
            self.update(viewModel: viewModel) { state in
                state.error = error
            }
        }
    }

    private func loadData(in viewModel: ViewModel<CollectionsPickerActionHandler>) {
        do {
            let libraryId = viewModel.state.library.identifier
            let collectionsRequest = ReadCollectionsDbRequest(libraryId: libraryId, excludedKeys: viewModel.state.excludedKeys)
            let results = try self.dbStorage.createCoordinator().perform(request: collectionsRequest)
            let collectionTree = CollectionTreeBuilder.collections(from: results, libraryId: libraryId)

            let token = results.observe({ [weak viewModel] changes in
                guard let viewModel = viewModel else { return }

                switch changes {
                case .update(let results, _, _, _):
                    self.update(results: results, in: viewModel)
                case .initial: break
                case .error: break
                }
            })

            self.update(viewModel: viewModel) { state in
                state.collectionTree = collectionTree
                state.changes = .results
                state.token = token
            }
        } catch let error {
            DDLogError("CollectionsStore: can't load collections: \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .dataLoading
            }
        }
    }

    private func update(results: Results<RCollection>, in viewModel: ViewModel<CollectionsPickerActionHandler>) {
        let tree = CollectionTreeBuilder.collections(from: results, libraryId: viewModel.state.library.identifier)
        self.update(viewModel: viewModel) { state in
            state.collectionTree = tree
            state.changes = .results

            // Removed selected keys if they were removed from tree.
            var removed: Set<String> = []
            for key in state.selected {
                guard tree.collection(for: .collection(key)) == nil else { continue }
                removed.insert(key)
            }

            if !removed.isEmpty {
                state.selected.subtract(removed)
                state.changes.insert(.selection)
            }
        }
    }
}
