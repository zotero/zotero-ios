//
//  CollectionsStore.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack
import RealmSwift
import RxSwift

struct CollectionCellData {
    enum DataType {
        case collection, search
    }

    let type: CollectionCellData.DataType
    let key: String
    let name: String
    let level: Int

    init(object: RCollection, level: Int) {
        self.type = .collection
        self.key = object.key
        self.name = object.name
        self.level = level
    }

    init(object: RSearch) {
        self.type = .search
        self.key = object.key
        self.name = object.name
        self.level = 0
    }
}

enum CollectionsAction {
    case load
}

enum CollectionsStoreError: Equatable {
    case cantLoadData
}

struct CollectionsState {
    let libraryId: Int
    let title: String

    fileprivate(set) var collectionCellData: [CollectionCellData]
    fileprivate(set) var searchCellData: [CollectionCellData]
    fileprivate(set) var error: CollectionsStoreError?

    // To avoid comparing the whole cellData arrays in == function, we just have a version which we increment
    // on each change and we'll compare just versions of cellData.
    fileprivate var version: Int
    fileprivate var collectionToken: NotificationToken?
    fileprivate var searchToken: NotificationToken?

    init(libraryId: Int, title: String) {
        self.libraryId = libraryId
        self.title = title
        self.collectionCellData = []
        self.searchCellData = []
        self.version = 0
    }
}

extension CollectionsState: Equatable {
    static func == (lhs: CollectionsState, rhs: CollectionsState) -> Bool {
        return lhs.error == rhs.error && lhs.version == rhs.version
    }
}

class CollectionsStore: Store {
    typealias Action = CollectionsAction
    typealias State = CollectionsState

    let dbStorage: DbStorage

    var updater: StoreStateUpdater<CollectionsState>

    init(initialState: CollectionsState, dbStorage: DbStorage) {
        self.dbStorage = dbStorage
        self.updater = StoreStateUpdater(initialState: initialState)
    }

    func handle(action: CollectionsAction) {
        switch action {
        case .load:
            self.loadData()
        }
    }

    private func reload(searches: Results<RSearch>) -> [CollectionCellData] {
        return searches.map(CollectionCellData.init)
    }

    private func reload(collections: Results<RCollection>) -> [CollectionCellData] {
        let topCollections = collections.filter("parent == nil").sorted(by: [SortDescriptor(keyPath: "name"),
                                                                             SortDescriptor(keyPath: "key")])
        return self.cells(for:topCollections, level: 0)
    }

    private func cells(for results: Results<RCollection>, level: Int) -> [CollectionCellData] {
        var cells: [CollectionCellData] = []
        for rCollection in results {
            let collection = CollectionCellData(object: rCollection, level: level)
            cells.append(collection)

            if rCollection.children.count > 0 {
                let sortedChildren = rCollection.children.sorted(by: [SortDescriptor(keyPath: "name"),
                                                                      SortDescriptor(keyPath: "key")])
                cells.append(contentsOf: self.cells(for: sortedChildren, level: (level + 1)))
            }
        }
        return cells
    }

    private func loadData() {
        guard self.state.value.collectionToken == nil && self.state.value.searchToken == nil else { return }

        do {
            let collectionsRequest = ReadCollectionsDbRequest(libraryId: self.state.value.libraryId)
            let collections = try self.dbStorage.createCoordinator().perform(request: collectionsRequest)
            let searchesRequest = ReadSearchesDbRequest(libraryId: self.state.value.libraryId)
            let searches = try self.dbStorage.createCoordinator().perform(request: searchesRequest)

            let collectionToken = collections.observe({ [weak self] changes in
                guard let `self` = self else { return }
                switch changes {
                case .update(let objects, _, _, _):
                    let cellData = self.reload(collections: objects)
                    self.updater.updateState(action: { newState in
                        newState.collectionCellData = cellData
                        newState.version += 1
                    })
                case .initial: break
                case .error(let error):
                    DDLogError("CollectionsStore: can't load collection update: \(error)")
                    self.updater.updateState { newState in
                        newState.error = .cantLoadData
                    }
                }
            })

            let searchToken = searches.observe({ [weak self] changes in
                guard let `self` = self else { return }
                switch changes {
                case .update(let objects, _, _, _):
                    let cellData = self.reload(searches: objects)
                    self.updater.updateState(action: { newState in
                        newState.searchCellData = cellData
                        newState.version += 1
                    })
                case .initial: break
                case .error(let error):
                    DDLogError("CollectionsStore: can't load collection update: \(error)")
                    self.updater.updateState { newState in
                        newState.error = .cantLoadData
                    }
                }
            })

            let collectionData = self.reload(collections: collections)
            let searchData = self.reload(searches: searches)
            self.updater.updateState { newState in
                newState.version += 1
                newState.collectionCellData = collectionData
                newState.searchCellData = searchData
                newState.collectionToken = collectionToken
                newState.searchToken = searchToken
            }
        } catch let error {
            DDLogError("CollectionsStore: can't load collections: \(error)")
            self.updater.updateState { newState in
                newState.error = .cantLoadData
            }
        }
    }
}
