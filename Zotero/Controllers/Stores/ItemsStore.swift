//
//  ItemsStore.swift
//  Zotero
//
//  Created by Michal Rentka on 11/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift
import RxSwift

struct ItemCellData {
    let identifier: String
    let title: String
    let hasChildren: Bool

    init(object: RItem) {
        self.identifier = object.identifier
        self.hasChildren = object.children.count > 0

        if !object.title.isEmpty {
            self.title = object.title
        } else if !object.nameOfAct.isEmpty {
            self.title = object.nameOfAct
        } else if !object.caseName.isEmpty {
            self.title = object.caseName
        } else if !object.subject.isEmpty {
            self.title = object.subject
        } else {
            self.title = ""
        }
    }
}

enum ItemsAction {
    case load
}

enum ItemsStoreError: Equatable {
    case cantLoadData
}

struct ItemsState {
    let libraryId: Int
    let collectionId: String?
    let parentId: String?
    let title: String

    fileprivate(set) var cellData: [ItemCellData]
    fileprivate(set) var error: ItemsStoreError?

    // To avoid comparing the whole cellData arrays in == function, we just have a version which we increment
    // on each change and we'll compare just versions of cellData.
    fileprivate var version: Int
    fileprivate var collections: Results<RItem>?
    fileprivate var collectionToken: NotificationToken?

    init(libraryId: Int, collectionId: String?, parentId: String?, title: String) {
        self.libraryId = libraryId
        self.collectionId = collectionId
        self.parentId = parentId
        self.title = title
        self.cellData = []
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

    let dbStorage: DbStorage

    var updater: StoreStateUpdater<ItemsState>

    init(initialState: ItemsState, dbStorage: DbStorage) {
        self.dbStorage = dbStorage
        self.updater = StoreStateUpdater(initialState: initialState)
    }

    func handle(action: ItemsAction) {
        switch action {
        case .load:
            self.loadData()
        }
    }

    private func reload(items: Results<RItem>) -> [ItemCellData] {
        return items.map(ItemCellData.init)
    }

    private func loadData() {
        do {
            let request = ReadItemsDbRequest(libraryId: self.state.value.libraryId,
                                             collectionId: self.state.value.collectionId,
                                             parentId: self.state.value.parentId, trash: false)
            let collections = try self.dbStorage.createCoordinator().perform(request: request)
            let collectionToken = collections.observe({ [weak self] changes in
                guard let `self` = self else { return }
                switch changes {
                case .update(let objects, _, _, _):
                    let cellData = self.reload(items: objects)
                    self.updater.updateState(action: { newState in
                        newState.cellData = cellData
                        newState.version += 1
                    })
                case .initial: break
                case .error(let error):
                    // TODO: - Log error?
                    self.updater.updateState { newState in
                        newState.error = .cantLoadData
                    }
                }
            })

            let cellData = self.reload(items: collections)
            self.updater.updateState { newState in
                newState.collections = collections
                newState.version += 1
                newState.cellData = cellData
                newState.collectionToken = collectionToken
            }
        } catch let error {
            // TODO: - Log error?
            self.updater.updateState { newState in
                newState.error = .cantLoadData
            }
        }
    }
}
