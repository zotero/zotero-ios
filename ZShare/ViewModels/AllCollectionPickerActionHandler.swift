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
    private let queue: DispatchQueue

    init(dbStorage: DbStorage, queue: DispatchQueue) {
        self.dbStorage = dbStorage
        self.queue = queue
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

        case .toggleCollection(let collectionId, let libraryId):
            self.toggleCollectionCollapsed(collectionId: collectionId, libraryId: libraryId, viewModel: viewModel)
        }
    }

    private func toggleCollectionCollapsed(collectionId: CollectionIdentifier, libraryId: LibraryIdentifier, viewModel: ViewModel<AllCollectionPickerActionHandler>) {
        guard let tree = viewModel.state.trees[libraryId], let isCollapsed = tree.isCollapsed(identifier: collectionId) else { return }
        tree.set(collapsed: !isCollapsed, to: collectionId)
        self.update(viewModel: viewModel) { state in
            state.toggledCollectionInLibraryId = libraryId
        }
    }

    private func load(in viewModel: ViewModel<AllCollectionPickerActionHandler>) {
        do {
            try self.dbStorage.perform(on: self.queue, with: { coordinator in
                let customLibraries = try coordinator.perform(request: ReadAllCustomLibrariesDbRequest())
                let groups = try coordinator.perform(request: ReadAllWritableGroupsDbRequest())
                let libraries = Array(customLibraries.map(Library.init)) + Array(groups.map(Library.init))

                var librariesCollapsed: [LibraryIdentifier: Bool] = [:]
                var trees: [LibraryIdentifier: CollectionTree] = [:]

                for library in libraries {
                    let collections = try coordinator.perform(request: ReadCollectionsDbRequest(libraryId: library.identifier))
                    let tree = CollectionTreeBuilder.collections(from: collections, libraryId: library.identifier, includeItemCounts: false)

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
