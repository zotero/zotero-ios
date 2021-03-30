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

    static func collections(from collections: Results<RCollection>, libraryId: LibraryIdentifier, selectedId: CollectionIdentifier?, collapseState: CollapseState) -> [Collection] {
        var parentMap = self.createCollectionMap(from: collections, libraryId: libraryId, selectedId: selectedId, collapseState: collapseState)
        return self.createCollections(for: "", level: 0, visible: true, from: &parentMap)
    }

    private static func createCollectionMap(from collections: Results<RCollection>, libraryId: LibraryIdentifier, selectedId: CollectionIdentifier?, collapseState: CollapseState) -> [String: [Collection]] {
        // Parent map used for backtracking when expanding parents of selected collection
        var parentMap: [String: String] = [:]
        // Collection map used for final creating collection array with proper sort order based on level
        var collectionMap: [String: [Collection]] = [:]

        for rCollection in collections {
            let itemCount = rCollection.items.count == 0 ? 0 : rCollection.items.filter(.items(for: .collection(rCollection.key, ""), libraryId: libraryId)).count
            let parentKey = rCollection.parentKey ?? ""
            var collection = Collection(object: rCollection, level: 0, visible: true, hasChildren: false, parentKey: rCollection.parentKey, itemCount: itemCount)
            switch collapseState {
            case .basedOnDb: break // db values already obtained from rCollection
            case .collapsedAll:
                collection.collapsed = true
            case .expandedAll:
                collection.collapsed = false
            }

            // Map collection.key => parentKey
            parentMap[rCollection.key] = parentKey
            // Map parentKey => children collections
            if var collections = collectionMap[parentKey] {
                let insertionIndex = collections.index(of: collection, sortedBy: { $0.name.compare($1.name, locale: Locale.autoupdatingCurrent) == .orderedAscending })
                collections.insert(collection, at: insertionIndex)
                collectionMap[parentKey] = collections
            } else {
                collectionMap[parentKey] = [collection]
            }
        }

        // Expand parents of selected collection
        if let selectedId = selectedId {
            switch selectedId {
            case .collection(let _key):
                // Start from parent, the selected collection shouldn't be expanded
                guard var key = parentMap[_key] else { return collectionMap }
                while let parentKey = parentMap[key] {
                    guard var collections = collectionMap[parentKey], let index = collections.firstIndex(where: { $0.identifier == .collection(key) }) else { break }
                    collections[index].collapsed = false
                    collectionMap[parentKey] = collections
                    key = parentKey
                }
            case .custom, .search: break
            }
        }

        return collectionMap
    }

    private static func createCollections(for key: String, level: Int, visible: Bool, from map: inout [String: [Collection]]) -> [Collection] {
        guard let original = map[key] else { return [] }

        var collections = original
        for (idx, var collection) in original.reversed().enumerated() {
            let childCollections = self.createCollections(for: (collection.identifier.key ?? ""), level: (level + 1), visible: (visible && !collection.collapsed), from: &map)

            collection.visible = visible
            collection.level = level
            collection.hasChildren = !childCollections.isEmpty
            collections[original.count - idx - 1] = collection

            if !childCollections.isEmpty {
                collections.insert(contentsOf: childCollections, at: (original.count - idx))
            }
        }

        map[key] = nil

        return collections
    }
}
