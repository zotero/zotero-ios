//
//  ItemsStore.swift
//  Zotero
//
//  Created by Michal Rentka on 11/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack
import RealmSwift
import RxSwift

class ItemsStore: Store {
    typealias Action = StoreAction
    typealias State = StoreState

    enum StoreAction {
        case load
    }

    enum StoreError: Error, Equatable {
        case cantLoadData
    }

    struct StoreState {
        enum ItemType {
            case all, trash, publications
            case collection(String, String) // Key, Title
            case search(String, String) // Key, Title
        }

        let libraryId: LibraryIdentifier
        let type: ItemType
        let title: String

        fileprivate(set) var items: Results<RItem>?
        fileprivate(set) var error: StoreError?
        fileprivate var version: Int
        fileprivate var itemsToken: NotificationToken?

        init(libraryId: LibraryIdentifier, type: ItemType) {
            self.libraryId = libraryId
            self.type = type
            switch type {
            case .collection(_, let title), .search(_, let title):
                self.title = title
            case .all:
                self.title = "All Items"
            case .trash:
                self.title = "Trash"
            case .publications:
                self.title = "My Publications"
            }
            self.version = 0
        }
    }

    let apiClient: ApiClient
    let fileStorage: FileStorage
    let dbStorage: DbStorage
    let itemFieldsController: ItemFieldsController

    var updater: StoreStateUpdater<StoreState>

    init(initialState: StoreState, apiClient: ApiClient, fileStorage: FileStorage,
         dbStorage: DbStorage, itemFieldsController: ItemFieldsController) {
        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.dbStorage = dbStorage
        self.itemFieldsController = itemFieldsController
        self.updater = StoreStateUpdater(initialState: initialState)
    }

    func handle(action: StoreAction) {
        switch action {
        case .load:
            self.loadData()
        }
    }

    private func loadData() {
        do {
            let request: ReadItemsDbRequest
            switch self.state.value.type {
            case .all:
                request = ReadItemsDbRequest(libraryId: self.state.value.libraryId,
                                             collectionKey: nil, parentKey: nil, trash: false)
            case .trash:
                request = ReadItemsDbRequest(libraryId: self.state.value.libraryId,
                                             collectionKey: nil, parentKey: nil, trash: true)
            case .publications, .search:
                // TODO: - implement publications and search fetching
                request = ReadItemsDbRequest(libraryId: .group(-1),
                                             collectionKey: nil, parentKey: nil, trash: true)
            case .collection(let key, _):
                request = ReadItemsDbRequest(libraryId: self.state.value.libraryId,
                                             collectionKey: key, parentKey: nil, trash: false)
            }
            let items = try self.dbStorage.createCoordinator().perform(request: request)
            let itemsToken = items.observe({ [weak self] changes in
                guard let `self` = self else { return }
                switch changes {
                case .update(_, _, _, _):
                    self.updater.updateState(action: { newState in
                        newState.version += 1
                    })
                case .initial: break
                case .error(let error):
                    DDLogError("ItemsStore: couldn't update data - \(error)")
                    self.updater.updateState { newState in
                        newState.error = .cantLoadData
                    }
                }
            })

            self.updater.updateState { newState in
                newState.version += 1
                newState.items = items
                newState.itemsToken = itemsToken
            }
        } catch let error {
            DDLogError("ItemsStore: couldn't load data - \(error)")
            self.updater.updateState { newState in
                newState.error = .cantLoadData
            }
        }
    }
}

extension ItemsStore.StoreState: Equatable {
    static func == (lhs: ItemsStore.StoreState, rhs: ItemsStore.StoreState) -> Bool {
        return lhs.error == rhs.error && lhs.version == rhs.version
    }
}
