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

    static func collections(from searches: Results<RSearch>) -> [Collection] {
        return searches.map(Collection.init)
    }

    static func collections(from rCollections: Results<RCollection>, libraryId: LibraryIdentifier, includeItemCounts: Bool) -> CollectionTree {
        var collections: [CollectionIdentifier: Collection] = [:]
        var collapsed: [CollectionIdentifier: Bool] = [:]
        let nodes: [CollectionTree.Node] = self.collections(for: nil, from: rCollections, libraryId: libraryId, includeItemCounts: includeItemCounts, allCollections: &collections, collapsedState: &collapsed)
        return CollectionTree(nodes: nodes, collections: collections, collapsed: collapsed)
    }

    private static func collections(for parent: CollectionIdentifier?, from rCollections: Results<RCollection>, libraryId: LibraryIdentifier, includeItemCounts: Bool,
                                    allCollections: inout [CollectionIdentifier: Collection], collapsedState: inout [CollectionIdentifier: Bool]) -> [CollectionTree.Node] {
        var nodes: [CollectionTree.Node] = []
        for rCollection in rCollections.filter(parent?.key.flatMap({ .parentKey($0) }) ?? .parentKeyNil) {
            let collection = self.collection(from: rCollection, libraryId: libraryId, includeItemCounts: includeItemCounts)
            allCollections[collection.identifier] = collection
            collapsedState[collection.identifier] = rCollection.collapsed

            let children = self.collections(for: collection.identifier, from: rCollections, libraryId: libraryId, includeItemCounts: includeItemCounts, allCollections: &allCollections, collapsedState: &collapsedState)
            let node = CollectionTree.Node(identifier: collection.identifier, parent: parent, children: children)
            let insertionIndex = self.insertionIndex(for: node, in: nodes, collections: allCollections)
            nodes.insert(node, at: insertionIndex)
        }
        return nodes
    }

    private static func insertionIndex(for node: CollectionTree.Node, in array: [CollectionTree.Node], collections: [CollectionIdentifier: Collection]) -> Int {
        return array.index(of: node, sortedBy: { lhs, rhs in
            guard let lCollection = collections[lhs.identifier], let rCollection = collections[rhs.identifier] else { return true }
            return lCollection.name.compare(rCollection.name, options: [.numeric], locale: Locale.autoupdatingCurrent) == .orderedAscending
        })
    }

    private static func collection(from rCollection: RCollection, libraryId: LibraryIdentifier, includeItemCounts: Bool) -> Collection {
        var itemCount: Int = 0
        if includeItemCounts {
            itemCount = rCollection.items.isEmpty ? 0 : rCollection.items.filter(.items(for: .collection(rCollection.key), libraryId: libraryId)).count
        }
        return Collection(object: rCollection, itemCount: itemCount)
    }
}
