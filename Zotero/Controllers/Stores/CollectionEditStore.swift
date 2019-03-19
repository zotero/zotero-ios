//
//  CollectionEditStore.swift
//  Zotero
//
//  Created by Michal Rentka on 18/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack
import RealmSwift

class CollectionEditStore: Store {
    typealias Action = StoreAction
    typealias State = StoreState

    enum StoreAction {
        case changeName(String)
        case changeParent(CollectionCellData)
        case delete
        case save
    }

    enum StoreError: Equatable {
        case invalidName
        case saveFailed
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
            case name, parent, actions
        }

        struct Parent: Equatable {
            let key: String
            let name: String

            init(collection: RCollection) {
                self.key = collection.key
                self.name = collection.name
            }

            init(collection: CollectionCellData) {
                self.key = collection.key
                self.name = collection.name
            }
        }

        let sections: [Section]
        let libraryId: Int
        let libraryName: String
        let key: String

        fileprivate(set) var parent: Parent?
        fileprivate(set) var name: String
        fileprivate(set) var changes: Changes
        fileprivate(set) var error: StoreError?
        fileprivate(set) var didSave: Bool

        init(collection: RCollection) {
            self.sections = [.name, .parent, .actions]
            self.libraryId = collection.library?.identifier ?? RLibrary.myLibraryId
            self.libraryName = collection.library?.name ?? ""
            self.key = collection.key
            self.name = collection.name
            self.parent = collection.parent.flatMap(StoreState.Parent.init)
            self.changes = []
            self.didSave = false
        }
    }

    let dbStorage: DbStorage
    let updater: StoreStateUpdater<CollectionEditStore.StoreState>

    init(initialState: CollectionEditStore.StoreState, dbStorage: DbStorage) {
        self.dbStorage = dbStorage
        self.updater = StoreStateUpdater(initialState: initialState)
        self.updater.stateCleanupAction = { state in
            state.error = nil
            state.changes = []
            state.didSave = false
        }
    }

    func handle(action: StoreAction) {
        switch action {
        case .save:
            guard !self.state.value.name.isEmpty else {
                self.updater.updateState { state in
                    state.error = StoreError.invalidName
                }
                return
            }

            let state = self.state.value
            let request = StoreCollectionDbRequest(libraryId: state.libraryId, key: state.key,
                                                   name: state.name, parentKey: state.parent?.key)

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let `self` = self else { return }
                do {
                    try self.dbStorage.createCoordinator().perform(request: request)
                    self.updater.updateState { state in
                        state.didSave = true
                    }
                } catch let error {
                    DDLogError("CollectionEditStore: couldn't save changes - \(error)")
                    self.updater.updateState { state in
                        state.error = .saveFailed
                    }
                }
            }

        case .delete: break // TODO: - Add deletion

        case .changeName(let name):
            self.updater.updateState { state in
                // We don't need to add change for name because user types it directly into textField,
                // so we don't need to reload the cell with the same value again
                state.name = name
            }

        case .changeParent(let parent):
            self.updater.updateState { state in
                state.parent = StoreState.Parent(collection: parent)
                state.changes.insert(.parent)
            }
        }
    }
}

extension CollectionEditStore.Changes {
    static let parent = CollectionEditStore.Changes(rawValue: 1 << 0)
}

extension CollectionEditStore.StoreState: Equatable {
    static func == (lhs: CollectionEditStore.StoreState, rhs: CollectionEditStore.StoreState) -> Bool {
        return lhs.parent == rhs.parent && lhs.name == rhs.name && lhs.error == rhs.error && lhs.didSave == rhs.didSave
    }
}
