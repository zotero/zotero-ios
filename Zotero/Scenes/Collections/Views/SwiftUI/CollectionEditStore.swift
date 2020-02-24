//
//  CollectionEditStore.swift
//  Zotero
//
//  Created by Michal Rentka on 18/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

import CocoaLumberjack
import RealmSwift

class CollectionEditStore: ObservableObject {
    struct State {
        let library: Library
        let key: String?

        var name: String
        var parent: Collection?
        var error: Error?
        var loading: Bool
    }

    enum Error: Swift.Error, Identifiable {
        case saveFailed, emptyName

        var id: Error {
            return self
        }
    }

    @Published var state: State

    private let dbStorage: DbStorage

    // SWIFTUI BUG: - figure out how to dismiss from store instead of view
    var shouldDismiss: (() -> Void)?

    init(library: Library, key: String? = nil, name: String = "", parent: Collection? = nil, dbStorage: DbStorage) {
        self.dbStorage = dbStorage
        self.state = State(library: library, key: key, name: name, parent: parent, loading: false)
    }

    func save() {
        if self.state.name.isEmpty {
            self.state.error = .emptyName
            return
        }

        if let key = self.state.key {
            let request = StoreCollectionDbRequest(libraryId: self.state.library.identifier,
                                                   key: key,
                                                   name: self.state.name,
                                                   parentKey: self.state.parent?.key)
            self.performWithLoading(request: request, dismissAfterSuccess: true)
        } else {
            let request = CreateCollectionDbRequest(libraryId: self.state.library.identifier,
                                                    key: KeyGenerator.newKey,
                                                    name: self.state.name,
                                                    parentKey: self.state.parent?.key)
            self.performWithLoading(request: request, dismissAfterSuccess: true)
        }
    }

    func delete() {
        guard let key = self.state.key else { return }
        let request = MarkObjectsAsDeletedDbRequest<RCollection>(keys: [key], libraryId: self.state.library.identifier)
        self.performWithLoading(request: request, dismissAfterSuccess: true)
    }

    func deleteWithItems() {
        guard let key = self.state.key else { return }
        let request = MarkCollectionAndItemsAsDeletedDbRequest(key: key, libraryId: self.state.library.identifier)
        self.performWithLoading(request: request, dismissAfterSuccess: true)
    }

    private func performWithLoading<Request: DbRequest>(request: Request, dismissAfterSuccess shouldDismiss: Bool) {
        self.state.loading = true
        self.perform(storeRequest: request) { [weak self] error in
            self?.state.error = error
            self?.state.loading = false

            if shouldDismiss && error == nil {
                self?.shouldDismiss?()
            }
        }
    }

    private func perform<Request: DbRequest>(storeRequest request: Request, completion: @escaping (Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let `self` = self else { return }
            do {
                try self.dbStorage.createCoordinator().perform(request: request)
                DispatchQueue.main.async {
                    completion(nil)
                }
            } catch let error {
                DDLogError("CollectionEditStore: couldn't save changes - \(error)")
                DispatchQueue.main.async {
                    completion(.saveFailed)
                }
            }
        }
    }
}
