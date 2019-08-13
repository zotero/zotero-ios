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
        case deleteCollection
        case deleteCollectionAndItems
        case save
    }

    enum StoreError: Error, Equatable {
        case collectionNotStoredInLibrary
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

        enum Action {
            case deleteCollection, deleteCollectionAndItems
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

        fileprivate let isEditing: Bool
        let sections: [Section]
        let actions: [Action]
        let libraryId: LibraryIdentifier
        let libraryName: String
        let key: String

        fileprivate(set) var parent: Parent?
        fileprivate(set) var name: String
        fileprivate(set) var changes: Changes
        fileprivate(set) var error: StoreError?
        fileprivate(set) var didSave: Bool

        init(libraryId: LibraryIdentifier, libraryName: String) {
            self.isEditing = false
            self.sections = [.name, .parent]
            self.actions = []
            self.key = KeyGenerator.newKey
            self.name = ""
            self.parent = nil
            self.changes = []
            self.didSave = false
            self.libraryId = libraryId
            self.libraryName = libraryName
        }

        init(collection: RCollection) throws {
            guard let libraryObject = collection.libraryObject else { throw StoreError.collectionNotStoredInLibrary }

            self.sections = [.name, .parent, .actions]
            self.actions = [.deleteCollection, .deleteCollectionAndItems]
            self.isEditing = true
            self.libraryId = libraryObject.identifier
            switch libraryObject {
            case .custom(let object):
                self.libraryName = object.type.libraryName
            case .group(let object):
                self.libraryName = object.name
            }
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
            if state.isEditing {
                self.perform(storeRequest: StoreCollectionDbRequest(libraryId: state.libraryId, key: state.key,
                                                                    name: state.name, parentKey: state.parent?.key))
            } else {
                self.perform(storeRequest: CreateCollectionDbRequest(libraryId: state.libraryId, key: state.key,
                                                                     name: state.name, parentKey: state.parent?.key))
            }

        case .deleteCollection:
            self.perform(storeRequest: MarkObjectAsDeletedDbRequest<RCollection>(key: self.state.value.key,
                                                                                 libraryId: self.state.value.libraryId))

        case .deleteCollectionAndItems:
            self.perform(storeRequest: MarkCollectionAndItemsAsDeletedDbRequest(key: self.state.value.key,
                                                                                libraryId: self.state.value.libraryId))

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

    private func perform<Request: DbRequest>(storeRequest request: Request) {
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
