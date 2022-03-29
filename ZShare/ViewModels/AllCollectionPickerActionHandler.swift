//
//  AllCollectionPickerActionHandler.swift
//  ZShare
//
//  Created by Michal Rentka on 27/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

import CocoaLumberjackSwift

final class AllCollectionPickerActionHandler: ViewModelActionHandler {
    typealias State = AllCollectionPickerState

    private unowned let dbStorage: DbStorage

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
    }

    func process(action: AllCollectionPickerAction, in viewModel: ViewModel<AllCollectionPickerActionHandler>) {
        switch action {
        case .loadData:
            self.load(in: viewModel)

        case .search(let term):
            self.search(term: term, in: viewModel)

        case .toggleLibrary(let libraryId):
            self.update(viewModel: viewModel) { state in
                state.librariesCollapsed[libraryId] = !(state.librariesCollapsed[libraryId] ?? true)
                state.toggledLibraryId = libraryId
            }
        }
    }

    private func load(in viewModel: ViewModel<AllCollectionPickerActionHandler>) {
        do {
            try self.dbStorage.perform(with: { coordinator in
                let customLibraries = try coordinator.perform(request: ReadAllCustomLibrariesDbRequest())
                let groups = try coordinator.perform(request: ReadAllWritableGroupsDbRequest())
                let libraries = Array(customLibraries.map(Library.init)) + Array(groups.map(Library.init))

                var librariesCollapsed: [LibraryIdentifier: Bool] = [:]
                var trees: [LibraryIdentifier: CollectionTree] = [:]

                for library in libraries {
                    let collections = try coordinator.perform(request: ReadCollectionsDbRequest(libraryId: library.identifier))
                    let tree = CollectionTreeBuilder.collections(from: collections, libraryId: library.identifier)

                    trees[library.identifier] = tree
                    librariesCollapsed[library.identifier] = viewModel.state.selectedLibraryId != library.identifier
                }

                self.update(viewModel: viewModel) { state in
                    state.libraries = libraries
                    state.librariesCollapsed = librariesCollapsed
                    state.trees = trees
                    state.changes = .results
                }
            })
        } catch let error {
            DDLogError("AllCollectionPickerStore: can't load collections - \(error)")
        }
    }

    private func search(term: String?, in viewModel: ViewModel<AllCollectionPickerActionHandler>) {
        self.update(viewModel: viewModel) { state in
            for (_, tree) in state.trees {
                if let term = term {
                    tree.search(for: term)
                } else {
                    tree.cancelSearch()
                }
            }
            state.changes = .search
        }
    }
}
