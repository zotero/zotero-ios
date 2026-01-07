//
//  CollectionTreeBuilder.swift
//  Zotero
//
//  Created by Michal Rentka on 09/09/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
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
        guard let libraryId = rItem.libraryId else {
            DDLogError("CollectionTreeBuilder: tried creating tree from item with no library \(rItem.key)")
            return CollectionTree(nodes: [], collections: [:], collapsed: [:])
        }

        var collections: [CollectionIdentifier: Collection] = [:]
        var rootIds: Set<CollectionIdentifier> = []
        var allChildren: [CollectionIdentifier: [CollectionIdentifier]] = [:]
        var stack = Array(rItem.collections.filter(.notTrashedOrDeleted).map({ Collection(object: $0, isAvailable: true) }))
        while let collection = stack.popLast() {
            guard let key = collection.id.key else {
                DDLogInfo("CollectionTreeBuilder: creating tree from non-collection - \(collection.id)")
                continue
            }
            if let existingCollection = collections[collection.id] {
                // Only process collections which were not processed yet, but if a collection has been processed and the `isAvailable` flag isn't set properly, update collection
                if !existingCollection.isAvailable && collection.isAvailable {
                    collections[collection.id] = collection
                }
                continue
            }
            guard let rCollection = allRCollections.filter(.key(key, in: libraryId)).first else {
                DDLogInfo("CollectionTreeBuilder: item contained collection not in all collections results - \(collection.id)")
                continue
            }
            collections[collection.id] = collection
            if let parentKey = rCollection.parentKey {
                guard let rParent = allRCollections.filter(.key(parentKey, in: libraryId)).first else {
                    DDLogError("CollectionTreeBuilder: parent missing in all collections - \(parentKey), \(libraryId)")
                    continue
                }
                if var children = allChildren[.collection(parentKey)] {
                    children.append(collection.id)
                    allChildren[.collection(parentKey)] = children
                } else {
                    allChildren[.collection(parentKey)] = [collection.id]
                }
                stack.append(Collection(object: rParent, isAvailable: false))
            } else {
                rootIds.insert(.collection(key))
            }
        }

        var nodes: [CollectionTree.Node] = []
        for id in rootIds {
            let node = buildNode(identifier: id, parentId: nil)
            let index = insertionIndex(for: node, in: nodes, collections: collections)
            nodes.insert(node, at: index)
        }

        return CollectionTree(nodes: nodes, collections: collections, collapsed: [:])
        
        func buildNode(identifier: CollectionIdentifier, parentId: CollectionIdentifier?) -> CollectionTree.Node {
            var childNodes: [CollectionTree.Node] = []
            if let children = allChildren[identifier] {
                for childId in children {
                    let node = buildNode(identifier: childId, parentId: identifier)
                    let index = insertionIndex(for: node, in: childNodes, collections: collections)
                    childNodes.insert(node, at: index)
                }
            }
            return CollectionTree.Node(identifier: identifier, parent: parentId, children: childNodes)
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
