//
//  CollectionEditActionHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 18/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct CollectionEditActionHandler: ViewModelActionHandler {
    typealias Action = CollectionEditAction
    typealias State = CollectionEditState

    private let dbStorage: DbStorage

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
    }

    func process(action: CollectionEditAction, in viewModel: ViewModel<CollectionEditActionHandler>) {
        switch action {
        case .setName(let value):
            self.update(viewModel: viewModel) { state in
                state.name = value
            }

        case .setParent(let value):
            self.update(viewModel: viewModel) { state in
                state.parent = value
            }

        case .setError(let error):
            self.update(viewModel: viewModel) { state in
                state.error = error
            }

        case .save:
            self.save(in: viewModel)

        case .delete:
            guard let key = viewModel.state.key else { return }
            let request = MarkObjectsAsDeletedDbRequest<RCollection>(keys: [key], libraryId: viewModel.state.library.identifier)
            self.perform(request: request, dismissAfterSuccess: true, in: viewModel)

        case .deleteWithItems:
            guard let key = viewModel.state.key else { return }
            let request = MarkCollectionAndItemsAsDeletedDbRequest(key: key, libraryId: viewModel.state.library.identifier)
            self.perform(request: request, dismissAfterSuccess: true, in: viewModel)

        }
    }

    private func save(in viewModel: ViewModel<CollectionEditActionHandler>) {
        if viewModel.state.name.isEmpty {
            self.update(viewModel: viewModel) { state in
                state.error = .emptyName
            }
            return
        }

        if let key = viewModel.state.key {
            let request = EditCollectionDbRequest(libraryId: viewModel.state.library.identifier,
                                                  key: key,
                                                  name: viewModel.state.name,
                                                  parentKey: viewModel.state.parent?.key)
            self.perform(request: request, dismissAfterSuccess: true, in: viewModel)
        } else {
            let request = CreateCollectionDbRequest(libraryId: viewModel.state.library.identifier,
                                                    key: KeyGenerator.newKey,
                                                    name: viewModel.state.name,
                                                    parentKey: viewModel.state.parent?.key)
            self.perform(request: request, dismissAfterSuccess: true, in: viewModel)
        }
    }

    private func perform<Request: DbRequest>(request: Request,
                                             dismissAfterSuccess shouldDismiss: Bool,
                                             in viewModel: ViewModel<CollectionEditActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.loading = true
        }

        do {
            try self.dbStorage.createCoordinator().perform(request: request)
            self.update(viewModel: viewModel) { state in
                state.loading = false
                if shouldDismiss {
                    state.shouldDismiss = true
                }
            }
        } catch let error {
            DDLogError("CollectionEditStore: couldn't save changes - \(error)")
            self.update(viewModel: viewModel) { state in
                state.loading = false
                state.error = .saveFailed(state.name)
            }
        }
    }
}
