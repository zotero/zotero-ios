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

struct CollectionEditActionHandler: ViewModelActionHandler, BackgroundDbProcessingActionHandler {
    typealias Action = CollectionEditAction
    typealias State = CollectionEditState

    unowned let dbStorage: DbStorage
    let backgroundQueue: DispatchQueue

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
        self.backgroundQueue = DispatchQueue(label: "org.zotero.CollectionEditActionHandler.backgroundProcessing", qos: .userInitiated)
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
            let request = EditCollectionDbRequest(libraryId: viewModel.state.library.identifier, key: key, name: viewModel.state.name, parentKey: viewModel.state.parent?.identifier.key)
            self.perform(request: request, dismissAfterSuccess: true, in: viewModel)
        } else {
            let request = CreateCollectionDbRequest(libraryId: viewModel.state.library.identifier, key: KeyGenerator.newKey, name: viewModel.state.name,
                                                    parentKey: viewModel.state.parent?.identifier.key)
            self.perform(request: request, dismissAfterSuccess: true, in: viewModel)
        }
    }

    private func perform<Request: DbRequest>(request: Request, dismissAfterSuccess shouldDismiss: Bool, in viewModel: ViewModel<CollectionEditActionHandler>) {
        self.update(viewModel: viewModel) { state in
            state.loading = true
        }

        self.perform(request: request) { [weak viewModel] error in
            guard let viewModel = viewModel else { return }
            self.update(viewModel: viewModel) { state in
                state.loading = false
                if let error = error {
                    DDLogError("CollectionEditActionHandler: couldn't perform request - \(error)")
                    state.error = .saveFailed
                } else if shouldDismiss {
                    state.shouldDismiss = true
                }
            }
        }
    }
}
