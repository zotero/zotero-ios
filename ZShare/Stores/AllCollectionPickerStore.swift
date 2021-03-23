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

final class AllCollectionPickerStore: ObservableObject {
    struct State {
        let selectedCollectionId: CollectionIdentifier
        let selectedLibraryId: LibraryIdentifier
        var libraries: [Library]
        var librariesCollapsed: [LibraryIdentifier: Bool]
        var collections: [LibraryIdentifier: [Collection]]
    }

    @Published var state: State

    private let dbStorage: DbStorage

    init(selectedCollectionId: CollectionIdentifier, selectedLibraryId: LibraryIdentifier, dbStorage: DbStorage) {
        self.dbStorage = dbStorage
        self.state = State(selectedCollectionId: selectedCollectionId, selectedLibraryId: selectedLibraryId, libraries: [], librariesCollapsed: [:], collections: [:])
    }

    func load() {
        do {
            let coordinator = try self.dbStorage.createCoordinator()

            let visibleLibraryId = self.state.selectedLibraryId
            let visibleCollectionId = self.state.selectedCollectionId

            let customLibraries = try coordinator.perform(request: ReadAllCustomLibrariesDbRequest())
            let groups = try coordinator.perform(request: ReadAllWritableGroupsDbRequest())

            let libraries = Array(customLibraries.map(Library.init)) + Array(groups.map(Library.init))
            var librariesCollapsed: [LibraryIdentifier: Bool] = [:]
            var collections: [LibraryIdentifier: [Collection]] = [:]

            for library in libraries {
                let libraryId = library.identifier
                let libraryCollections = try coordinator.perform(request: ReadCollectionsDbRequest(libraryId: libraryId))
                collections[libraryId] = CollectionTreeBuilder.collections(from: libraryCollections, libraryId: libraryId, selectedId: (libraryId == visibleLibraryId ? visibleCollectionId : nil), collapseState: .collapsedAll)
                librariesCollapsed[libraryId] = visibleLibraryId != libraryId
            }

            if var _collections = collections[visibleLibraryId],
               let index = _collections.firstIndex(where: { $0.identifier == visibleCollectionId }) {
                self.show(index: index, in: &_collections)
                collections[visibleLibraryId] = _collections
            }

            var state = self.state
            state.libraries = libraries
            state.librariesCollapsed = librariesCollapsed
            state.collections = collections
            self.state = state
        } catch let error {
            DDLogError("AllCollectionPickerStore: can't load collections - \(error)")
        }
    }

    func toggleLibraryCollapsed(id: LibraryIdentifier) {
        self.state.librariesCollapsed[id] = !(self.state.librariesCollapsed[id] ?? true)
    }

    func toggleCollectionCollapsed(collection: Collection, libraryId: LibraryIdentifier) {
        guard var collections = self.state.collections[libraryId], let index = collections.firstIndex(of: collection) else { return }
        self.set(collapsed: !collection.collapsed, startIndex: index, in: &collections)
        self.state.collections[libraryId] = collections
    }

    private func parent(for collectionId: CollectionIdentifier, in collections: [Collection]) -> (Collection, Int)? {
        guard let index = collections.firstIndex(where: { $0.identifier == collectionId }) else { return nil }
        let level = collections[index].level
        if level == 0 {
            return nil
        }

        for idx in (0..<index).reversed() {
            if collections[idx].level < level {
                return (collections[idx], idx)
            }
        }
        return nil
    }

    private func show(index: Int, in collections: inout [Collection]) {
        // Show collection
        collections[index].visible = true

        var level = collections[index].level

        // Show siblings under collection
        for idx in ((index + 1)..<collections.count) {
            let _level = collections[idx].level
            if level > _level {
                break
            }
            if level == _level {
                collections[idx].visible = true
            }
        }

        // Show and expand appropriate parent collections
        for idx in (0..<index).reversed() {
            let _level = collections[idx].level

            if level == _level {
                // Show all siblings on same level
                collections[idx].visible = true
            } else if _level < level {
                level = _level
                // Show parent and make it expanded
                collections[idx].collapsed = false
                collections[idx].visible = true
            }
        }
    }

    private func set(collapsed: Bool, startIndex index: Int, in collections: inout [Collection]) {
        // Set `collapsed` flag for collection. Toggled collection is always visible.
        collections[index].collapsed = collapsed
        collections[index].visible = true

        let level = collections[index].level

        var ignoreLevel: Int?

        // Find collections which should be shown/hidden
        for idx in ((index + 1)..<collections.count) {
            let _collection = collections[idx]

            if level >= _collection.level {
                break
            }

            if collapsed {
                // Hide all children
                collections[idx].visible = false
            } else {
                if let level = ignoreLevel {
                    // If parent was collapsed, don't show children
                    if _collection.level >= level {
                        continue
                    } else {
                        ignoreLevel = nil
                    }
                }
                // Show all children which are not collapsed
                collections[idx].visible = true
                if _collection.collapsed {
                    // Don't show children of collapsed collection
                    ignoreLevel = _collection.level + 1
                }
            }
        }
    }
}
