//
//  CollectionPickerStore.swift
//  Zotero
//
//  Created by Michal Rentka on 19/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

import CocoaLumberjack
import RealmSwift
import RxSwift

class NewCollectionPickerStore: ObservableObject {
    enum Error: Swift.Error, Equatable {
        case dataLoading
    }

    struct State {
        let library: Library

        fileprivate(set) var collections: [Collection]
        fileprivate(set) var error: Error?
        fileprivate var token: NotificationToken?
    }

    var state: State {
        willSet {
            self.objectWillChange.send()
        }
    }
    // SWIFTUI BUG: should be defined by default, but bugged in current version
    let objectWillChange: ObservableObjectPublisher

    init(library: Library, dbStorage: DbStorage) {
        self.objectWillChange = ObservableObjectPublisher()

        do {
            let collectionsRequest = ReadCollectionsDbRequest(libraryId: library.identifier)
            let results = try dbStorage.createCoordinator().perform(request: collectionsRequest)
            let collections = CollectionTreeBuilder.collections(from: results)
            self.state = State(library: library, collections: collections)

            self.state.token = results.observe({ changes in
                switch changes {
                case .update(let results, _, _, _):
                    self.state.collections = CollectionTreeBuilder.collections(from: results)
                case .initial: break
                case .error: break
                }
            })
        } catch let error {
            DDLogError("CollectionsStore: can't load collections: \(error)")
            self.state = State(library: library, collections: [], error: .dataLoading)
        }
    }
}

class CollectionPickerStore: OldStore {
    typealias Action = StoreAction
    typealias State = StoreState

    enum StoreError: Error, Equatable {
        case loadingFailed
    }

    enum StoreAction {
        case load
        case pick(Int)
    }

    struct StoreState {
        struct Changes: OptionSet {
            typealias RawValue = UInt8

            var rawValue: UInt8

            init(rawValue: UInt8) {
                self.rawValue = rawValue
            }
        }

        fileprivate let libraryId: LibraryIdentifier
        fileprivate let excludedKey: String

        fileprivate(set) var cellData: [Collection]
        fileprivate(set) var pickedData: Collection?
        fileprivate(set) var changes: Changes
        fileprivate var version: Int
        fileprivate(set) var error: StoreError?

        init(libraryId: LibraryIdentifier, excludedKey: String) {
            self.libraryId = libraryId
            self.excludedKey = excludedKey
            self.cellData = []
            self.changes = []
            self.version = 0
        }
    }

    private let dbStorage: DbStorage
    let updater: StoreStateUpdater<StoreState>

    init(initialState: StoreState, dbStorage: DbStorage) {
        self.dbStorage = dbStorage
        self.updater = StoreStateUpdater(initialState: initialState)
        self.updater.stateCleanupAction = { state in
            state.changes = []
        }
    }

    func handle(action: StoreAction) {
        switch action {
        case .load:
            do {
                let request = ReadCollectionsDbRequest(libraryId: self.state.value.libraryId)
                let collections = try self.dbStorage.createCoordinator().perform(request: request)
                let cells = CollectionTreeBuilder.collections(from: collections)
                self.updater.updateState { state in
                    state.cellData = cells
                    state.changes.insert(.data)
                    state.version += 1
                }
            } catch let error {
                DDLogError("CollectionPickerStore: loading failed - \(error)")
                self.updater.updateState { state in
                    state.error = .loadingFailed
                }
            }

        case .pick(let index):
            let data = self.state.value.cellData[index]
            guard data.key != self.state.value.excludedKey else { return }
            self.updater.updateState { state in
                state.pickedData = data
                state.changes.insert(.pickedCollection)
            }
        }
    }
}

extension CollectionPickerStore.StoreState.Changes {
    static let data = CollectionPickerStore.StoreState.Changes(rawValue: 1 << 0)
    static let pickedCollection = CollectionPickerStore.StoreState.Changes(rawValue: 1 << 1)
}

extension CollectionPickerStore.StoreState: Equatable {
    static func == (lhs: CollectionPickerStore.StoreState, rhs: CollectionPickerStore.StoreState) -> Bool {
        return lhs.version == rhs.version && lhs.error == rhs.error && lhs.pickedData?.key == rhs.pickedData?.key
    }
}
