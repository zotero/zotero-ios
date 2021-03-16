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
    static func collections(from searches: Results<RSearch>) -> [Collection] {
        return searches.map(Collection.init)
    }

    static func collections(from collections: Results<RCollection>, libraryId: LibraryIdentifier) -> [Collection] {
        var parentMap = self.createParentMap(from: collections)
        return self.createCollections(for: "", level: 0, visible: true, from: &parentMap)
    }

    private static func createParentMap(from collections: Results<RCollection>) -> [String: [Collection]] {
        var parentMap: [String: [Collection]] = [:]
        for rCollection in collections {
            let collection = Collection(object: rCollection, level: 0, visible: true, hasChildren: false, parentKey: rCollection.parentKey, itemCount: 0)
            let parentKey = rCollection.parentKey ?? ""
            if var collections = parentMap[parentKey] {
                let insertionIndex = collections.index(of: collection, sortedBy: { $0.name < $1.name })
                collections.insert(collection, at: insertionIndex)
                parentMap[parentKey] = collections
            } else {
                parentMap[parentKey] = [collection]
            }
        }
        return parentMap
    }

    private static func createCollections(for key: String, level: Int, visible: Bool, from map: inout [String: [Collection]]) -> [Collection] {
        guard let original = map[key] else { return [] }

        var collections = original
        for (idx, var collection) in original.reversed().enumerated() {
            let childCollections = self.createCollections(for: collection.key, level: (level + 1), visible: (visible && !collection.collapsed), from: &map)

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
