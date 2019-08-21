//
//  CollectionsStore.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

import CocoaLumberjack
import RealmSwift
import RxSwift

class NewCollectionsStore: Store, StateUpdater {
    typealias Action = StoreAction
    typealias State = StoreState
    
    enum StoreAction {
        case load
        case deleteCollection(Int)
        case deleteSearch(Int)
        case editCollection(Int)
        case editSearch(Int)
    }
    
    enum StoreError: Error, Equatable {
        case dataLoading
        case collectionNotFound
        case deletion
    }
    
    class StoreState {
        let libraryId: LibraryIdentifier
        let title: String
        let metadataEditable: Bool
        let filesEditable: Bool

        fileprivate(set) var cellData: [CollectionCellData]
        fileprivate(set) var error: StoreError?
        fileprivate var collectionToken: NotificationToken?
        fileprivate var searchToken: NotificationToken?

        init(libraryId: LibraryIdentifier, title: String, metadataEditable: Bool, filesEditable: Bool) {
            self.cellData = [CollectionCellData(custom: .all),
                             CollectionCellData(custom: .publications),
                             CollectionCellData(custom: .trash)]
            self.libraryId = libraryId
            self.title = title
            self.metadataEditable = metadataEditable
            self.filesEditable = filesEditable
        }
    }
    
    let state: StoreState
    // SWIFTUI BUG: should be defined by default, but bugged in current version
    let objectWillChange: ObservableObjectPublisher
    let dbStorage: DbStorage
    
    init(initialState: StoreState, dbStorage: DbStorage) {
        self.state = initialState
        self.dbStorage = dbStorage
        self.objectWillChange = ObservableObjectPublisher()
    }

    func handle(action: StoreAction) {
        switch action {
        case .load:
            // SWIFTUI BUG: - need to delay it a little because it's called on `onAppear` and it reloads the state immediately which causes a tableview reload crash, remove dispatch after when fixed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.loadData()
            }
        case .editCollection(let index): break
//            self.editCollection(at: index)
        case .editSearch(let index): break // TODO: - Implement search editing!
        case .deleteCollection(let index): break
//            self.deleteCollection(at: index)
        case .deleteSearch(let index): break
//            self.deleteSearch(at: index)
        }
    }
    
//    private func editCollection(at index: Int) {
//        let data = self.state.value.collectionCellData[index]
//        do {
//            let request = ReadCollectionDbRequest(libraryId: self.state.value.libraryId, key: data.key)
//            let collection = try self.dbStorage.createCoordinator().perform(request: request)
//            self.updater.updateState { state in
//                state.collectionToEdit = collection
//                state.changes.insert(.editing)
//            }
//        } catch let error {
//            DDLogError("CollectionsStore: can't load collection - \(error)")
//            self.updater.updateState { state in
//                state.error = .collectionNotFound
//            }
//        }
//    }
//
//    private func deleteCollection(at index: Int) {
//        let data = self.state.value.collectionCellData[index]
//        let libraryId = self.state.value.libraryId
//        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
//            self?.delete(object: RCollection.self, key: data.key, libraryId: libraryId)
//        }
//    }
//
//    private func deleteSearch(at index: Int) {
//        let data = self.state.value.searchCellData[index]
//        let libraryId = self.state.value.libraryId
//        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
//            self?.delete(object: RSearch.self, key: data.key, libraryId: libraryId)
//        }
//    }

    private func delete<Obj: DeletableObject>(object: Obj.Type, key: String, libraryId: LibraryIdentifier) {
        do {
            let request = MarkObjectAsDeletedDbRequest<Obj>(key: key, libraryId: libraryId)
            try self.dbStorage.createCoordinator().perform(request: request)
        } catch let error {
            DDLogError("CollectionsStore: can't delete object - \(error)")
            self.updateState { $0.error = .deletion }
        }
    }

    private func loadData() {
        guard self.state.collectionToken == nil && self.state.searchToken == nil else { return }

        do {
            let collectionsRequest = ReadCollectionsDbRequest(libraryId: self.state.libraryId)
            let collections = try self.dbStorage.createCoordinator().perform(request: collectionsRequest)
            let searchesRequest = ReadSearchesDbRequest(libraryId: self.state.libraryId)
            let searches = try self.dbStorage.createCoordinator().perform(request: searchesRequest)

            let collectionToken = collections.observe({ [weak self] changes in
                guard let `self` = self else { return }
                switch changes {
                case .update(let objects, _, _, _):
                    self.update(cellData: CollectionCellData.createCells(from: objects))
                case .initial: break
                case .error(let error):
                    DDLogError("CollectionsStore: can't load collection update: \(error)")
                    self.updateState { $0.error = .dataLoading }
                }
            })

            let searchToken = searches.observe({ [weak self] changes in
                guard let `self` = self else { return }
                switch changes {
                case .update(let objects, _, _, _):
                    self.update(cellData: CollectionCellData.createCells(from: objects))
                case .initial: break
                case .error(let error):
                    DDLogError("CollectionsStore: can't load collection update: \(error)")
                    self.updateState { $0.error = .dataLoading }
                }
            })

            let cells = CollectionCellData.createCells(from: collections) + CollectionCellData.createCells(from: searches)
            self.updateState { state in
                state.cellData.insert(contentsOf: cells, at: 1) // insert after .all custom cell
                state.collectionToken = collectionToken
                state.searchToken = searchToken
            }
        } catch let error {
            DDLogError("CollectionsStore: can't load collections: \(error)")
            self.updateState { $0.error = .dataLoading }
        }
    }
    
    private func update(cellData cells: [CollectionCellData]) {
        guard let type = cells.first?.type else { return }
        
        // Find range of cells with the same type
        
        var startIndex: Int = -1
        var endIndex: Int = -1
        
        for data in self.state.cellData.enumerated() {
            if startIndex == -1 {
                if data.element.type == type {
                    startIndex = data.offset
                }
            } else if endIndex == -1 {
                if data.element.type != type {
                    endIndex = data.offset
                }
            }
        }
        
        if startIndex != -1 && endIndex == -1 { // last cell was of the same type, so endIndex is at the end
            endIndex = self.state.cellData.count
        }
        
        if startIndex == -1 && endIndex == -1 { return } // no object of that type found
        
        // Replace old cells of this type with new cells
        self.updateState { state in
            state.cellData.remove(atOffsets: IndexSet(integersIn: startIndex..<endIndex))
            state.cellData.insert(contentsOf: cells, at: startIndex)
        }
    }
}

class CollectionsStore: OldStore {
    enum StoreAction {
        case load
        case deleteCollection(Int)
        case deleteSearch(Int)
        case editCollection(Int)
        case editSearch(Int)
    }

    enum StoreError: Error, Equatable {
        case dataLoading
        case collectionNotFound
        case deletion
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

        let libraryId: LibraryIdentifier
        let title: String
        let allItemsCellData: [CollectionCellData]
        let sections: [Section]
        let metadataEditable: Bool
        let filesEditable: Bool

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

        init(libraryId: LibraryIdentifier, title: String, metadataEditable: Bool, filesEditable: Bool) {
            self.libraryId = libraryId
            self.title = title
            self.collectionCellData = []
            self.searchCellData = []
            self.changes = []
            self.version = 0
            self.allItemsCellData = [CollectionCellData(custom: .all)]
            var customCellData: [CollectionCellData] = []
            if case .custom = libraryId {
                customCellData.append(CollectionCellData(custom: .publications))
            }
            customCellData.append(CollectionCellData(custom: .trash))
            self.customCellData = customCellData
            self.sections = [.allItems, .collections, .searches, .custom]
            self.metadataEditable = metadataEditable
            self.filesEditable = filesEditable
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
            self.editCollection(at: index)
        case .editSearch(let index): break // TODO: - Implement search editing!
        case .deleteCollection(let index):
            self.deleteCollection(at: index)
        case .deleteSearch(let index):
            self.deleteSearch(at: index)
        }
    }

    private func editCollection(at index: Int) {
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
    }

    private func deleteCollection(at index: Int) {
        let data = self.state.value.collectionCellData[index]
        let libraryId = self.state.value.libraryId
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.delete(object: RCollection.self, key: data.key, libraryId: libraryId)
        }
    }

    private func deleteSearch(at index: Int) {
        let data = self.state.value.searchCellData[index]
        let libraryId = self.state.value.libraryId
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.delete(object: RSearch.self, key: data.key, libraryId: libraryId)
        }
    }

    private func delete<Obj: DeletableObject>(object: Obj.Type, key: String, libraryId: LibraryIdentifier) {
        do {
            let request = MarkObjectAsDeletedDbRequest<Obj>(key: key, libraryId: libraryId)
            try self.dbStorage.createCoordinator().perform(request: request)
        } catch let error {
            DDLogError("CollectionsStore: can't delete object - \(error)")
            self.updater.updateState { newState in
                newState.error = .deletion
            }
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
                        newState.error = .dataLoading
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
                        newState.error = .dataLoading
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
                newState.error = .dataLoading
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
