//
//  CollectionTreeBuilder.swift
//  Zotero
//
//  Created by Michal Rentka on 09/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct CollectionTreeBuilder {
    struct Result {
        let collections: [CollectionIdentifier: Collection]
        let root: [CollectionIdentifier]
        let children: [CollectionIdentifier: [CollectionIdentifier]]
        let collapsed: [CollectionIdentifier: Bool]
    }

    enum CollapseState {
        /// All collections are visible.
        case expandedAll
        /// All collections are collapsed (except selected branch). Only 0-level collections are visible (and selected branch).
        case collapsedAll
        /// Stored state from database is taken into account.
        case basedOnDb
    }

    static func collections(from searches: Results<RSearch>) -> [Collection] {
        return searches.map(Collection.init)
    }

    static func collections(from rCollections: Results<RCollection>, libraryId: LibraryIdentifier, includeItemCounts: Bool) -> Result {
        var collections: [CollectionIdentifier: Collection] = [:]
        var root: [CollectionIdentifier] = []
        var collapsed: [CollectionIdentifier: Bool] = [:]
        var children: [CollectionIdentifier: [CollectionIdentifier]] = [:]

        for rCollection in rCollections {
            let collection = self.collection(from: rCollection, includeItemCounts: includeItemCounts, libraryId: libraryId)
            collections[collection.identifier] = collection
            collapsed[collection.identifier] = rCollection.collapsed

            guard let parentKey = rCollection.parentKey else {
                let insertionIndex = self.insertionIndex(for: collection, in: root, collections: collections)
                root.insert(collection.identifier, at: insertionIndex)
                continue
            }

            if var _children = children[.collection(parentKey)] {
                let insertionIndex = self.insertionIndex(for: collection, in: _children, collections: collections)
                _children.insert(collection.identifier, at: insertionIndex)
                children[.collection(parentKey)] = _children
            } else {
                children[.collection(parentKey)] = [collection.identifier]
            }
        }

        return Result(collections: collections, root: root, children: children, collapsed: collapsed)
    }

    private static func insertionIndex(for collection: Collection, in array: [CollectionIdentifier], collections: [CollectionIdentifier: Collection]) -> Int {
        return array.index(of: collection.identifier, sortedBy: { lhs, rhs in
            guard let lCollection = lhs == collection.identifier ? collection : collections[lhs],
                  let rCollection = rhs == collection.identifier ? collection : collections[rhs] else { return true }
            return lCollection.name.compare(rCollection.name, options: [.numeric], locale: Locale.autoupdatingCurrent) == .orderedAscending
        })
    }

//    private static func getCollapsedAndChildren(from rCollection: RCollection, collections: Results<RCollection>, libraryId: LibraryIdentifier, includeItemCounts: Bool, collapsed: inout [String: Bool], children: inout [String: [Collection]]) {
//        collapsed[rCollection.key] = rCollection.collapsed
//
//        let childrenResults = collections.filter(.parentKey(rCollection.key))
//        guard childrenResults.isEmpty else { return }
//
//        children[rCollection.key] = self.collections(from: childrenResults, libraryId: libraryId, includeItemCounts: includeItemCounts, additional: { rCollection in
//            self.getCollapsedAndChildren(from: rCollection, collections: collections, libraryId: libraryId, includeItemCounts: includeItemCounts, collapsed: &collapsed, children: &children)
//        })
//    }
//
//    private static func collections(from results: Results<RCollection>, libraryId: LibraryIdentifier, includeItemCounts: Bool, additional: (RCollection) -> Void) -> [CollectionIdentifier] {
//        var collections: [CollectionIdentifier] = []
//        for rCollection in results {
//            collections.append(self.collection(from: rCollection, includeItemCounts: includeItemCounts, libraryId: libraryId))
//            additional(rCollection)
//        }
//        return collections
//    }

    private static func collection(from rCollection: RCollection, includeItemCounts: Bool, libraryId: LibraryIdentifier) -> Collection {
        var itemCount: Int = 0
        if includeItemCounts {
           itemCount = rCollection.items.count == 0 ? 0 : rCollection.items.filter(.items(for: .collection(rCollection.key, ""), libraryId: libraryId)).count
        }
        return Collection(object: rCollection, itemCount: itemCount)
    }

//    private static func createCollectionMap(from collections: Results<RCollection>, libraryId: LibraryIdentifier, selectedId: CollectionIdentifier?, collapseState: CollapseState, includeItemCounts: Bool) -> [String: [Collection]] {
//        // Parent map used for backtracking when expanding parents of selected collection
//        var parentMap: [String: String] = [:]
//        // Collection map used for final creating collection array with proper sort order based on level
//        var collectionMap: [String: [Collection]] = [:]
//
//        for rCollection in collections {
//            var itemCount: Int = 0
//            if includeItemCounts {
//               itemCount = rCollection.items.count == 0 ? 0 : rCollection.items.filter(.items(for: .collection(rCollection.key, ""), libraryId: libraryId)).count
//            }
//            let parentKey = rCollection.parentKey ?? ""
//            var collection = Collection(object: rCollection, level: 0, visible: true, hasChildren: false, parentKey: rCollection.parentKey, itemCount: itemCount)
//            switch collapseState {
//            case .basedOnDb: break // db values already obtained from rCollection
//            case .collapsedAll:
//                collection.collapsed = true
//            case .expandedAll:
//                collection.collapsed = false
//            }
//
//            // Map collection.key => parentKey
//            parentMap[rCollection.key] = parentKey
//            // Map parentKey => children collections
//            if var collections = collectionMap[parentKey] {
//                let insertionIndex = collections.index(of: collection, sortedBy: { $0.name.compare($1.name, options: [.numeric], locale: Locale.autoupdatingCurrent) == .orderedAscending })
//                collections.insert(collection, at: insertionIndex)
//                collectionMap[parentKey] = collections
//            } else {
//                collectionMap[parentKey] = [collection]
//            }
//        }
//
//        // Expand parents of selected collection
//        if let selectedId = selectedId {
//            switch selectedId {
//            case .collection(let _key):
//                // Start from parent, the selected collection shouldn't be expanded
//                guard var key = parentMap[_key] else { return collectionMap }
//                while let parentKey = parentMap[key] {
//                    guard var collections = collectionMap[parentKey], let index = collections.firstIndex(where: { $0.identifier == .collection(key) }) else { break }
//                    collections[index].collapsed = false
//                    collectionMap[parentKey] = collections
//                    key = parentKey
//                }
//            case .custom, .search: break
//            }
//        }
//
//        return collectionMap
//    }
//
//    private static func createCollections(for key: String, level: Int, visible: Bool, from map: inout [String: [Collection]]) -> [Collection] {
//        guard let original = map[key] else { return [] }
//
//        var collections = original
//        for (idx, var collection) in original.reversed().enumerated() {
//            let childCollections = self.createCollections(for: (collection.identifier.key ?? ""), level: (level + 1), visible: (visible && !collection.collapsed), from: &map)
//
//            collection.visible = visible
//            collection.level = level
//            collection.hasChildren = !childCollections.isEmpty
//            collections[original.count - idx - 1] = collection
//
//            if !childCollections.isEmpty {
//                collections.insert(contentsOf: childCollections, at: (original.count - idx))
//            }
//        }
//
//        map[key] = nil
//
//        return collections
//    }
}
