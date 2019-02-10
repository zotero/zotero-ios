//
//  CollectionsStore.swift
//  Zotero
//
//  Created by Michal Rentka on 10/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift
import RxSwift

class LibraryCellData {
    let identifier: Int
    let name: String
    fileprivate(set) var collections: [CollectionCellData] {
        didSet {
            self.recalculateIndices()
        }
    }
    fileprivate var collectionIndices: [Int]

    init(identifier: Int, name: String) {
        self.identifier = identifier
        self.name = name
        self.collections = []
        self.collectionIndices = []
    }

    fileprivate func recalculateIndices() {
        self.collectionIndices = []

        var collapsedParentId: String?
        for data in self.collections.enumerated() {
            if data.element.collapsed {
                if collapsedParentId == nil {
                    collapsedParentId = data.element.identifier
                }
                continue
            }

            if let collapsedId = collapsedParentId, data.element.hasParent(with: collapsedId) {
                continue
            }

            collapsedParentId = nil
            self.collectionIndices.append(data.offset)
        }
    }
}

class CollectionCellData {
    let identifier: String
    let name: String
    fileprivate(set) var level: Int
    fileprivate weak var parent: CollectionCellData?
    fileprivate var collapsed: Bool

    init(identifier: String, name: String, level: Int, parent: CollectionCellData?) {
        self.identifier = identifier
        self.parent = parent
        self.name = name
        self.level = level
        self.collapsed = false
    }

    fileprivate func hasParent(with identifier: String) -> Bool {
        var parent = self.parent
        while parent != nil {
            if parent?.identifier == identifier {
                return true
            }
            parent = parent?.parent
        }
        return false
    }
}

extension CollectionCellData: Equatable {
    static func ==(lhs: CollectionCellData, rhs: CollectionCellData) -> Bool {
        return lhs.identifier == rhs.identifier
    }
}

enum CollectionsAction {
    case load
}

enum CollectionStoreError: Equatable {
    case cantLoadData
}

class CollectionsState: NSObject {
    fileprivate(set) var cellData: [LibraryCellData]
    fileprivate(set) var error: CollectionStoreError?

    // To avoid comparing the whole cellData arrays in == function, we just have a version which we increment
    // on each change and we'll compare just versions of cellData.
    fileprivate var version: Int
    fileprivate var libraries: Results<RLibrary>?
    fileprivate var collections: Results<RCollection>?
    fileprivate var libraryToken: NotificationToken?
    fileprivate var collectionToken: NotificationToken?

    override init() {
        self.cellData = []
        self.version = 0
        super.init()
    }
}

extension CollectionsState {
    static func == (lhs: CollectionsState, rhs: CollectionsState) -> Bool {
        return lhs.error == rhs.error && lhs.version == rhs.version
    }
}

class CollectionsStore: Store {
    typealias Action = CollectionsAction
    typealias State = CollectionsState

    private let dbStorage: DbStorage

    var updater: StoreStateUpdater<CollectionsState>

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
        self.updater = StoreStateUpdater(initialState: CollectionsState())
    }

    func handle(action: CollectionsAction) {
        switch action {
        case .load:
            self.loadData()
        }
    }

    private func reloadCellData(rLibraries: Results<RLibrary>, rCollections: Results<RCollection>) {
        if rLibraries.isEmpty {
            self.updater.updateState { newState in
                newState.cellData = []
                newState.version += 1
            }
            return
        }

        var cellData: [LibraryCellData] = []
        for rLibrary in rLibraries {
            let library = LibraryCellData(identifier: rLibrary.identifier, name: rLibrary.name)
            cellData.append(library)
        }

        if rCollections.isEmpty {
            self.updater.updateState { newState in
                newState.cellData = cellData
                newState.version += 1
            }
            return
        }

        var parentStack: [CollectionCellData] = []
        var libraryId: Int = Int.min
        var collections: [CollectionCellData] = []

        for rCollection in rCollections {
            var parent: CollectionCellData?
            var level = 0

            if let parentId = rCollection.parent?.identifier {
                if let reversedIndex = parentStack.reversed().index(where: { $0.identifier == parentId }) {
                    let index = parentStack.index(before: reversedIndex.base)
                    parent = parentStack[index]
                    level = index
                    if index != (parentStack.count - 1) {
                        parentStack = Array(parentStack[0...index])
                    }
                } else if let last = collections.last, last.identifier == parentId {
                    parentStack.append(last)
                    parent = last
                    level = parentStack.count
                } else {
                    fatalError("CollectionsStore: unkown state while reloading data, sorting broken?")
                }
            }

            if let currentId = rCollection.library?.identifier, libraryId != currentId {
                if !collections.isEmpty {
                    if let index = cellData.index(where: { $0.identifier == libraryId }) {
                        cellData[index].collections = collections
                    }
                    collections = []
                }
                libraryId = currentId
            }

            let collection = CollectionCellData(identifier: rCollection.identifier, name: rCollection.name,
                                                level: level, parent: parent)
            collections.append(collection)
        }

        if let index = cellData.index(where: { $0.identifier == libraryId }) {
            cellData[index].collections = collections
        }

        self.updater.updateState { newState in
            newState.cellData = cellData
            newState.version += 1
        }
    }

    private func loadData() {
        do {
            let libraries = try self.dbStorage.createCoordinator().perform(request: ReadAllLibrariesDbRequest())
            let collections = try self.dbStorage.createCoordinator().perform(request: ReadAllCollectionsDbRequest())
            self.reloadCellData(rLibraries: libraries, rCollections: collections)

            let libraryToken = libraries.observe({ [weak self] changes in
                guard let `self` = self else { return }
                switch changes {
                case .update(let objects, _, _, _):
                    if let collections = self.state.value.collections {
                        self.reloadCellData(rLibraries: objects, rCollections: collections)
                    }
                case .initial: break
                case .error(let error):
                    // TODO: - Log error?
                    self.updater.updateState { newState in
                        newState.error = .cantLoadData
                    }
                }
            })

            let collectionToken = collections.observe({ [weak self] changes in
                guard let `self` = self else { return }
                switch changes {
                case .update(let objects, _, _, _):
                    if let libraries = self.state.value.libraries {
                        self.reloadCellData(rLibraries: libraries, rCollections: objects)
                    }
                case .initial: break
                case .error(let error):
                    // TODO: - Log error?
                    self.updater.updateState { newState in
                        newState.error = .cantLoadData
                    }
                }
            })

            self.updater.updateState { newState in
                newState.libraries = libraries
                newState.collections = collections
                newState.libraryToken = libraryToken
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

extension CollectionsState: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return self.cellData.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.cellData[section].collectionIndices.count + 1 // +1 for current library
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)

        guard indexPath.section < self.cellData.count else { return cell }

        let library = self.cellData[indexPath.section]
        if indexPath.row == 0 {
            cell.textLabel?.text = library.name
            return cell
        }

        let collectionId = indexPath.row - 1
        guard collectionId < library.collectionIndices.count else { return cell }

        let collection = library.collections[library.collectionIndices[collectionId]]
        cell.textLabel?.text = "(\(collection.level)) \(collection.name)"

        return cell
    }
}
