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

class CollectionsStore: Store {
    typealias Action = CollectionsStore.StoreAction
    typealias State = CollectionsStore.StoreState

    enum StoreAction {
        case load
        case deleteCollection(Int)
        case deleteSearch(Int)
        case editCollection(Int)
        case editSearch(Int)
    }

    enum StoreError: Equatable {
        case cantLoadData
        case collectionNotFound
    }

    struct Changes: OptionSet {
        typealias RawValue = UInt8

        var rawValue: UInt8

        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
    }

    struct StoreState {
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
        fileprivate(set) var error: StoreError?
        fileprivate(set) var collectionToEdit: RCollection?
        fileprivate(set) var changes: Changes
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

    let dbStorage: DbStorage

    var updater: StoreStateUpdater<StoreState>

    init(initialState: StoreState, dbStorage: DbStorage) {
        self.dbStorage = dbStorage
        self.updater = StoreStateUpdater(initialState: initialState)
        self.updater.stateCleanupAction = { state in
            state.changes = []
            state.collectionToEdit = nil
            state.error = nil
        }
    }

    func handle(action: StoreAction) {
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
                    let cellData = CollectionCellData.createCells(from: objects)
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
                    let cellData = CollectionCellData.createCells(from: objects)
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

            let collectionData = CollectionCellData.createCells(from: collections)
            let searchData = CollectionCellData.createCells(from: searches)
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

extension CollectionsStore.Changes {
    static let data = CollectionsStore.Changes(rawValue: 1 << 0)
    static let editing = CollectionsStore.Changes(rawValue: 1 << 1)
}

extension CollectionsStore.StoreState: Equatable {
    static func == (lhs: CollectionsStore.StoreState, rhs: CollectionsStore.StoreState) -> Bool {
        return lhs.error == rhs.error && lhs.version == rhs.version &&
               lhs.collectionToEdit?.key == rhs.collectionToEdit?.key
    }
}
