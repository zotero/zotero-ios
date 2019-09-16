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

class CollectionsStore: ObservableObject {
    enum StoreError: Error, Equatable {
        case dataLoading
        case collectionNotFound
        case deletion
    }
    
    struct StoreState {
        let libraryId: LibraryIdentifier
        let title: String
        let metadataEditable: Bool
        let filesEditable: Bool

        fileprivate(set) var cellData: [Collection]
        fileprivate(set) var error: StoreError?
        fileprivate var collectionToken: NotificationToken?
        fileprivate var searchToken: NotificationToken?
    }
    
    private(set) var state: StoreState {
        willSet {
            self.objectWillChange.send()
        }
    }
    // SWIFTUI BUG: should be defined by default, but bugged in current version
    let objectWillChange: ObservableObjectPublisher
    let dbStorage: DbStorage
    
    init(libraryId: LibraryIdentifier, title: String, metadataEditable: Bool, filesEditable: Bool, dbStorage: DbStorage) {
        self.dbStorage = dbStorage
        self.objectWillChange = ObservableObjectPublisher()

        do {
            let collectionsRequest = ReadCollectionsDbRequest(libraryId: libraryId)
            let collections = try dbStorage.createCoordinator().perform(request: collectionsRequest)
            let searchesRequest = ReadSearchesDbRequest(libraryId: libraryId)
            let searches = try dbStorage.createCoordinator().perform(request: searchesRequest)

            var allCollections: [Collection] = [Collection(custom: .all),
                                                Collection(custom: .publications),
                                                Collection(custom: .trash)]
            allCollections.insert(contentsOf: CollectionTreeBuilder.collections(from: collections) +
                                              CollectionTreeBuilder.collections(from: searches),
                                  at: 1)

            self.state = StoreState(libraryId: libraryId, title: title,
                                    metadataEditable: metadataEditable,
                                    filesEditable: filesEditable,
                                    cellData: allCollections)

            let collectionToken = collections.observe({ [weak self] changes in
                guard let `self` = self else { return }
                switch changes {
                case .update(let objects, _, _, _):
                    self.update(cellData: CollectionTreeBuilder.collections(from: objects))
                case .initial: break
                case .error: break
                }
            })

            let searchToken = searches.observe({ [weak self] changes in
                guard let `self` = self else { return }
                switch changes {
                case .update(let objects, _, _, _):
                    self.update(cellData: CollectionTreeBuilder.collections(from: objects))
                case .initial: break
                case .error: break
                }
            })

            self.state.collectionToken = collectionToken
            self.state.searchToken = searchToken
        } catch let error {
            DDLogError("CollectionsStore: can't load collections: \(error)")
            self.state = StoreState(libraryId: libraryId, title: title, metadataEditable: metadataEditable,
                                    filesEditable: filesEditable, cellData: [], error: .dataLoading)
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
    func deleteCells(at indexSet: IndexSet) {
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
            DispatchQueue.main.async { [weak self] in
                self?.state.error = .deletion
            }
        }
    }
    
    private func update(cellData cells: [Collection]) {
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
        self.state.cellData.remove(atOffsets: IndexSet(integersIn: startIndex..<endIndex))
        self.state.cellData.insert(contentsOf: cells, at: startIndex)
    }
}
