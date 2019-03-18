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
        case collection(Bool) // hasChildren
        case search
        case custom(CustomType)
    }

    enum CustomType {
        case all, trash, publications
    }

    let type: CollectionCellData.DataType
    let key: String
    let name: String
    let level: Int

    init(object: RCollection, level: Int) {
        self.type = .collection(!object.children.isEmpty)
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

    init(custom type: CustomType) {
        self.type = .custom(type)
        self.key = ""
        self.level = 0
        switch type {
        case .all:
            self.name = "All Items"
        case .publications:
            self.name = "My Publications"
        case .trash:
            self.name = "Trash"
        }
    }
}

enum CollectionsAction {
    case load
    case deleteCollection(Int)
    case deleteSearch(Int)
    case editCollection(Int)
    case editSearch(Int)
}

enum CollectionsStoreError: Equatable {
    case cantLoadData
    case collectionNotFound
}

struct CollectionsStateChange: OptionSet {
    typealias RawValue = UInt8

    var rawValue: UInt8

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
}

extension CollectionsStateChange {
    static let data = CollectionsStateChange(rawValue: 1 << 0)
    static let editing = CollectionsStateChange(rawValue: 1 << 1)
}

struct CollectionsState {
    enum Section {
        case allItems, collections, searches, custom
    }

    let libraryId: Int
    let title: String

    let allItemsCellData: [CollectionCellData]
    let sections: [Section]
    fileprivate(set) var collectionCellData: [CollectionCellData]
    fileprivate(set) var searchCellData: [CollectionCellData]
    fileprivate(set) var customCellData: [CollectionCellData]
    fileprivate(set) var error: CollectionsStoreError?
    fileprivate(set) var collectionToEdit: RCollection?
    fileprivate(set) var changes: CollectionsStateChange

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
        self.changes = []
        self.version = 0
        self.allItemsCellData = [CollectionCellData(custom: .all)]
        self.customCellData = [CollectionCellData(custom: .publications),
                               CollectionCellData(custom: .trash)]
        self.sections = [.allItems, .collections, .searches, .custom]
    }
}

extension CollectionsState: Equatable {
    static func == (lhs: CollectionsState, rhs: CollectionsState) -> Bool {
        return lhs.error == rhs.error && lhs.version == rhs.version &&
               lhs.collectionToEdit?.key == rhs.collectionToEdit?.key
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
        self.updater.stateCleanupAction = { state in
            state.changes = []
            state.collectionToEdit = nil
            state.error = nil
        }
    }

    func handle(action: CollectionsAction) {
        switch action {
        case .load:
            self.loadData()
        case .editCollection(let index):
            let data = self.state.value.collectionCellData[index]
            do {
                let request = ReadCollectionDbRequest(libraryId: self.state.value.libraryId, key: data.key)
                let collection = try self.dbStorage.createCoordinator().perform(request: request)
                self.updater.updateState { state in
                    state.collectionToEdit = collection
                    state.changes.insert(.editing)
                }
            } catch let error {
                DDLogError("CollectionsStore: can't load collection - \(error)")
                self.updater.updateState { state in
                    state.error = .collectionNotFound
                }
            }
            
        case .editSearch(let index): break // TODO: - Implement search editing!
        case .deleteCollection(let index): break // TODO: - Implement deletions!
        case .deleteSearch(let index): break
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
                        newState.changes.insert(.data)
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
                        newState.changes.insert(.data)
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
                newState.changes.insert(.data)
            }
        } catch let error {
            DDLogError("CollectionsStore: can't load collections: \(error)")
            self.updater.updateState { newState in
                newState.error = .cantLoadData
            }
        }
    }
}
