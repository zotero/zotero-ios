//
//  AllCollectionPickerStore.swift
//  ZShare
//
//  Created by Michal Rentka on 27/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

import CocoaLumberjackSwift

class AllCollectionPickerStore: ObservableObject {
    struct State {
        var libraries: [Library]
        var collections: [LibraryIdentifier: [Collection]]
    }

    @Published var state: State

    private let dbStorage: DbStorage

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
        self.state = State(libraries: [], collections: [:])
    }

    func load() {
        do {
            let coordinator = try self.dbStorage.createCoordinator()

            let customLibraries = try coordinator.perform(request: ReadAllCustomLibrariesDbRequest())
            let groups = try coordinator.perform(request: ReadAllGroupsDbRequest())

            let libraries = Array(customLibraries.map(Library.init)) + Array(groups.map(Library.init))
            var collections: [LibraryIdentifier: [Collection]] = [:]

            for library in libraries {
                let libraryId = library.identifier
                let libraryCollections = try coordinator.perform(request: ReadCollectionsDbRequest(libraryId: libraryId))
                collections[libraryId] = CollectionTreeBuilder.collections(from: libraryCollections, libraryId: libraryId)
            }

            self.state.libraries = libraries
            self.state.collections = collections
        } catch let error {
            DDLogError("AllCollectionPickerStore: can't load collections - \(error)")
        }
    }
}
