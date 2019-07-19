//
//  LibrariesStore.swift
//  Zotero
//
//  Created by Michal Rentka on 11/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjack
import RealmSwift
import RxSwift

struct LibraryCellData {
    let identifier: LibraryIdentifier
    let name: String

    init(object: RGroup) {
        self.identifier = .group(object.identifier)
        self.name = object.name
    }

    init(object: RCustomLibrary) {
        let type = object.type
        self.identifier = .custom(type)
        self.name = type.libraryName
    }
}

class LibrariesStore: Store {
    typealias Action = StoreAction
    typealias State = StoreState

    enum StoreAction {
        case load
    }

    enum StoreError: Error, Equatable {
        case cantLoadData
    }

    struct StoreState {
        enum Section {
            case custom, groups
        }

        let sections: [Section] = [.custom, .groups]

        fileprivate(set) var customLibraries: [LibraryCellData]
        fileprivate(set) var groupLibraries: [LibraryCellData]
        fileprivate(set) var error: StoreError?
        // To avoid comparing the whole arrays in == function, we just have a version which we increment
        // on each change and we'll compare just versions.
        fileprivate var version: Int
        fileprivate var libraries: Results<RCustomLibrary>?
        fileprivate var groups: Results<RGroup>?
        fileprivate var librariesToken: NotificationToken?
        fileprivate var groupsToken: NotificationToken?

        init() {
            self.customLibraries = []
            self.groupLibraries = []
            self.version = 0
        }
    }

    let dbStorage: DbStorage

    var updater: StoreStateUpdater<StoreState>

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
        self.updater = StoreStateUpdater(initialState: StoreState())
    }

    func handle(action: StoreAction) {
        switch action {
        case .load:
            self.loadData()
        }
    }

    private func reload(libraries: Results<RCustomLibrary>?,
                        groups: Results<RGroup>?) -> ([LibraryCellData], [LibraryCellData]) {
        return ((libraries.flatMap({ Array($0.map(LibraryCellData.init)) }) ?? []),
                (groups.flatMap({ Array($0.map(LibraryCellData.init)) }) ?? []))
    }

    private func loadData() {
        do {
            let libraries = try self.dbStorage.createCoordinator().perform(request: ReadAllCustomLibrariesDbRequest())
            let groups = try self.dbStorage.createCoordinator().perform(request: ReadAllGroupsDbRequest())

            let librariesToken = libraries.observe({ [weak self] changes in
                guard let `self` = self else { return }
                switch changes {
                case .update(let objects, _, _, _):
                    let (libraryCellData, _) = self.reload(libraries: objects, groups: nil)
                    self.updater.updateState(action: { state in
                        state.customLibraries = libraryCellData
                        state.version += 1
                    })
                case .initial: break
                case .error(let error):
                    DDLogError("LibrariesStore: can't update libraries from db - \(error)")
                    self.updater.updateState { state in
                        state.error = .cantLoadData
                    }
                }
            })

            let groupsToken = groups.observe { [weak self] changes in
                guard let `self` = self else { return }
                switch changes {
                case .update(let objects, _, _, _):
                    let (_, groupCellData) = self.reload(libraries: nil, groups: objects)
                    self.updater.updateState(action: { state in
                        state.groupLibraries = groupCellData
                        state.version += 1
                    })
                case .initial: break
                case .error(let error):
                    DDLogError("LibrariesStore: can't update groups from db - \(error)")
                    self.updater.updateState { state in
                        state.error = .cantLoadData
                    }
                }
            }

            let (libraryCellData, groupCellData) = self.reload(libraries: libraries, groups: groups)
            self.updater.updateState { state in
                state.libraries = libraries
                state.groups = groups
                state.version += 1
                state.customLibraries = libraryCellData
                state.groupLibraries = groupCellData
                state.librariesToken = librariesToken
                state.groupsToken = groupsToken
            }
        } catch let error {
            DDLogError("LibrariesStore: can't load libraries from db - \(error)")
            self.updater.updateState { newState in
                newState.error = .cantLoadData
            }
        }
    }
}

extension LibrariesStore.StoreState: Equatable {
    static func == (lhs: LibrariesStore.StoreState, rhs: LibrariesStore.StoreState) -> Bool {
        return lhs.error == rhs.error && lhs.version == rhs.version
    }
}
