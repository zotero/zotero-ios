//
//  CollectionPickerActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack

struct CollectionPickerActionHandler: ViewModelActionHandler {
    typealias Action = CollectionPickerAction
    typealias State = CollectionPickerState

    private unowned let dbStorage: DbStorage

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
    }

    func process(action: CollectionPickerAction, in viewModel: ViewModel<CollectionPickerActionHandler>) {
        switch action {
        case .loadData:
            self.loadData(in: viewModel)

        case .setSelected(let selected):
            self.update(viewModel: viewModel) { state in
                state.selected = selected
            }

        case .setError(let error):
            self.update(viewModel: viewModel) { state in
                state.error = error
            }
        }
    }

    private func loadData(in viewModel: ViewModel<CollectionPickerActionHandler>) {
        do {
            let collectionsRequest = ReadCollectionsDbRequest(libraryId: viewModel.state.library.identifier,
                                                              excludedKeys: viewModel.state.excludedKeys)
            let results = try self.dbStorage.createCoordinator().perform(request: collectionsRequest)
            let collections = CollectionTreeBuilder.collections(from: results)

            let token = results.observe({ [weak viewModel] changes in
                guard let viewModel = viewModel else { return }
                switch changes {
                case .update(let results, _, _, _):
                    self.update(viewModel: viewModel) { state in
                        state.collections = CollectionTreeBuilder.collections(from: results)
                    }
                case .initial: break
                case .error: break
                }
            })

            self.update(viewModel: viewModel) { state in
                state.collections = collections
                state.token = token
            }
        } catch let error {
            DDLogError("CollectionsStore: can't load collections: \(error)")
            self.update(viewModel: viewModel) { state in
                state.error = .dataLoading
            }
        }
    }
}
