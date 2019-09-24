//
//  LibrariesStore.swift
//  Zotero
//
//  Created by Michal Rentka on 11/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

import CocoaLumberjack
import RealmSwift


class LibrariesStore: ObservableObject {
    enum Error: Swift.Error {
        case cantLoadData
    }

    struct State {
        var customLibraries: Results<RCustomLibrary>?
        var groupLibraries: Results<RGroup>?
        var error: Error?
        fileprivate var librariesToken: NotificationToken?
        fileprivate var groupsToken: NotificationToken?
    }

    var state: State {
        willSet {
            self.objectWillChange.send()
        }
    }
    // SWIFTUI BUG: should be defined by default, but bugged in current version
    let objectWillChange: ObservableObjectPublisher
    private let dbStorage: DbStorage

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
        self.objectWillChange = ObservableObjectPublisher()

        do {
            let libraries = try self.dbStorage.createCoordinator().perform(request: ReadAllCustomLibrariesDbRequest())
            let groups = try self.dbStorage.createCoordinator().perform(request: ReadAllGroupsDbRequest())

            self.state = State(customLibraries: libraries,
                               groupLibraries: groups)

            let librariesToken = libraries.observe({ [weak self] changes in
                guard let `self` = self else { return }
                switch changes {
                case .update(let objects, _, _, _):
                    self.state.customLibraries = objects
                case .initial: break
                case .error: break
                }
            })

            let groupsToken = groups.observe { [weak self] changes in
                guard let `self` = self else { return }
                switch changes {
                case .update(let objects, _, _, _):
                    self.state.groupLibraries = objects
                case .initial: break
                case .error: break
                }
            }

            self.state.librariesToken = librariesToken
            self.state.groupsToken = groupsToken
        } catch let error {
            DDLogError("LibrariesStore: - can't load data: \(error)")
            self.state = State(error: .cantLoadData)
        }
    }
}
