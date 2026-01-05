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

    static func collections(from rItem: RItem, allCollections allRCollections: Results<RCollection>) -> CollectionTree {
        var collections: [CollectionIdentifier: Collection] = [:]
        var nodes: [CollectionTree.Node] = []
        for rCollection in rItem.collections {
            let collection = Collection(object: rCollection, isInItem: true)
            collections[collection.identifier] = collection
            let nodesToRoot = getNodes(fromCollectionToRoot: rCollection, allCollections: &collections)
            nodes = merge(branchNode: nodesToRoot, toAllNodes: nodes)
        }
        return CollectionTree(nodes: nodes, collections: collections, collapsed: [:])

        func getNodes(fromCollectionToRoot rCollection: RCollection, allCollections: inout [CollectionIdentifier: Collection]) -> CollectionTree.Node {
            let node = CollectionTree.Node(identifier: .collection(rCollection.key), parent: rCollection.parentKey.flatMap({ .collection($0) }), children: [])
            return getParentNodeIfAvailable(from: node, parentKey: rCollection.parentKey)

            func getParentNodeIfAvailable(from childNode: CollectionTree.Node, parentKey: String?) -> CollectionTree.Node {
                // Find parent if available, otherwise just return self
                guard let parentKey, let parent = allRCollections.filter(.key(parentKey)).first else { return childNode }
                // Create new Collection if needed
                if allCollections[.collection(parent.key)] == nil {
                    let collection = Collection(object: parent, isInItem: false)
                    allCollections[collection.id] = collection
                }
                let node = CollectionTree.Node(identifier: .collection(parentKey), parent: parent.parentKey.flatMap({ .collection($0) }), children: [childNode])
                return getParentNodeIfAvailable(from: node, parentKey: parent.parentKey)
            }
        }

        func merge(branchNode: CollectionTree.Node, toAllNodes allNodes: [CollectionTree.Node]) -> [CollectionTree.Node] {
            if allNodes.isEmpty {
                return [branchNode]
            }
            return allNodes.map { currentNode in
                return merge(node: currentNode, withBranch: branchNode)
            }
        }

        func merge(node: CollectionTree.Node, withBranch branchNode: CollectionTree.Node) -> CollectionTree.Node {
            if node.identifier == branchNode.identifier {
                let children = branchNode.children.isEmpty ?
                    node.children :
                    merge(branchNode: branchNode.children[0], toAllNodes: node.children)
                return CollectionTree.Node(identifier: node.identifier, parent: node.parent, children: children)
            } else {
                let children = node.children.map { child in
                    return merge(node: child, withBranch: branchNode)
                }
                return CollectionTree.Node(identifier: node.identifier, parent: node.parent, children: children)
            }
        }
    }

    private static func collections(
        for parent: CollectionIdentifier?,
        from rCollections: Results<RCollection>,
        libraryId: LibraryIdentifier,
        includeItemCounts: Bool,
        allCollections: inout [CollectionIdentifier: Collection],
        collapsedState: inout [CollectionIdentifier: Bool]
    ) -> [CollectionTree.Node] {
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
