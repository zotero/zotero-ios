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

enum ItemsAction {
    case load
}

enum ItemsStoreError: Equatable {
    case cantLoadData
}

struct ItemsState {
    let libraryId: Int
    let collectionId: String?
    let title: String

    fileprivate(set) var items: Results<RItem>?
    fileprivate(set) var error: ItemsStoreError?
    fileprivate var version: Int
    fileprivate var itemsToken: NotificationToken?

    init(libraryId: Int, collectionId: String?, title: String) {
        self.libraryId = libraryId
        self.collectionId = collectionId
        self.title = title
        self.version = 0
    }
}

extension ItemsState: Equatable {
    static func == (lhs: ItemsState, rhs: ItemsState) -> Bool {
        return lhs.error == rhs.error && lhs.version == rhs.version
    }
}

class ItemsStore: Store {
    typealias Action = ItemsAction
    typealias State = ItemsState

    let apiClient: ApiClient
    let fileStorage: FileStorage
    let dbStorage: DbStorage
    let itemFieldsController: ItemFieldsController

    var updater: StoreStateUpdater<ItemsState>

    init(initialState: ItemsState, apiClient: ApiClient, fileStorage: FileStorage,
         dbStorage: DbStorage, itemFieldsController: ItemFieldsController) {
        self.apiClient = apiClient
        self.fileStorage = fileStorage
        self.dbStorage = dbStorage
        self.itemFieldsController = itemFieldsController
        self.updater = StoreStateUpdater(initialState: initialState)
    }

    func handle(action: ItemsAction) {
        switch action {
        case .load:
            self.loadData()
        }
    }

    private func loadData() {
        do {
            let request = ReadItemsDbRequest(libraryId: self.state.value.libraryId,
                                             collectionKey: self.state.value.collectionId,
                                             parentKey: nil, trash: false)
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
