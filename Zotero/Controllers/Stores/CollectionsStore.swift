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

class CollectionsStore: Store, StateUpdater {
    typealias Action = StoreAction
    typealias State = StoreState
    
    enum StoreAction {
        case load
        case deleteCells(IndexSet)
        case editCell(Int)
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
        case .editCell(let index): break
        case .deleteCells(let indexSet):
            self.deleteCells(at: indexSet)
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
    private func deleteCells(at indexSet: IndexSet) {
        let cells = self.state.cellData
        let libraryId = self.state.libraryId

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var collectionKeys: [String] = []
            var searchKeys: [String] = []
            
            indexSet.forEach { index in
                let cell = cells[index]
                switch cell.type {
                case .collection:
                    collectionKeys.append(cell.key)
                case .search:
                    searchKeys.append(cell.key)
                case .custom: break
                }
            }
            
            if !collectionKeys.isEmpty {
                self?.delete(object: RCollection.self, keys: collectionKeys, libraryId: libraryId)
            }
            
            if !searchKeys.isEmpty {
                self?.delete(object: RSearch.self, keys: searchKeys, libraryId: libraryId)
            }
        }
    }

    private func delete<Obj: DeletableObject>(object: Obj.Type, keys: [String], libraryId: LibraryIdentifier) {
        do {
            let request = MarkObjectsAsDeletedDbRequest<Obj>(keys: keys, libraryId: libraryId)
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
