//
//  CollectionTree.swift
//  Zotero
//
//  Created by Michal Rentka on 09.02.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class CollectionTree {
    struct Node: Hashable {
        let identifier: CollectionIdentifier
        let parent: CollectionIdentifier?
        let children: [Node]
    }

    enum CollapseState {
        /// All collections are visible.
        case expandedAll
        /// All collections are collapsed (except selected branch). Only 0-level collections are visible (and selected branch).
        case collapsedAll
        /// Stored state from database is taken into account.
        case basedOnDb
    }

    private var nodes: [Node]
    private var collections: [CollectionIdentifier: Collection]
    private var collapsed: [CollectionIdentifier: Bool]

    private var filtered: [CollectionIdentifier: SearchableCollection]

    init(nodes: [Node], collections: [CollectionIdentifier: Collection], collapsed: [CollectionIdentifier: Bool]) {
        self.nodes = nodes
        self.collections = collections
        self.collapsed = collapsed
        self.filtered = [:]
    }
}

// MARK: - Editing

extension CollectionTree {
    func append(collection: Collection, collapsed: Bool = true) {
        self.collections[collection.identifier] = collection
        self.collapsed[collection.identifier] = collapsed
        self.nodes.append(Node(identifier: collection.identifier, parent: nil, children: []))
    }

    func insert(collection: Collection, collapsed: Bool = true, at index: Int) {
        self.collections[collection.identifier] = collection
        self.collapsed[collection.identifier] = collapsed
        self.nodes.insert(Node(identifier: collection.identifier, parent: nil, children: []), at: index)
    }
}

// MARK: - Data Source

extension CollectionTree {
    func collection(for identifier: CollectionIdentifier) -> Collection? {
        return self.collections[identifier]
    }

    func update(collection: Collection) {
        self.collections[collection.identifier] = collection
    }

    func isCollapsed(identifier: CollectionIdentifier) -> Bool? {
        return self.collapsed[identifier]
    }

    func set(collapsed: Bool, to identifier: CollectionIdentifier) {
        self.collapsed[identifier] = collapsed
    }

    @discardableResult func setAll(collapsed: Bool) -> Set<CollectionIdentifier> {
        var changed: Set<CollectionIdentifier> = []
        for identifier in self.collapsed.keys {
            guard let value = self.collapsed[identifier], value != collapsed else { continue }
            self.collapsed[identifier] = collapsed
            changed.insert(identifier)
        }
        return changed
    }

    func isRoot(identifier: CollectionIdentifier) -> Bool {
        return self.nodes.contains(where: { $0.identifier == identifier })
    }

    func parent(of identifier: CollectionIdentifier) -> CollectionIdentifier? {
        return self.firstNode(where: { node in return node.children.contains(where: { $0.identifier == identifier }) }, in: self.nodes)?.identifier
    }

    func identifier(_ identifier: CollectionIdentifier, isChildOf parentId: CollectionIdentifier) -> Bool {
        guard let node = self.firstNode(with: parentId, in: self.nodes) else { return false }
        return self.firstNode(with: identifier, in: [node]) != nil
    }

    private func firstNode(with identifier: CollectionIdentifier, in array: [Node]) -> Node? {
        return self.firstNode(where: { $0.identifier == identifier }, in: array)
    }

    private func firstNode(where matching: (Node) -> Bool, in array: [Node]) -> Node? {
        var queue: [Node] = array
        while !queue.isEmpty {
            let node = queue.removeFirst()

            if matching(node) {
                return node
            }

            if !node.children.isEmpty {
                queue.append(contentsOf: node.children)
            }
        }
        return nil
    }

    func replace(identifiersMatching matching: (CollectionIdentifier) -> Bool, with tree: CollectionTree) {
        self.replaceValues(in: &self.collections, from: tree.collections, matchingId: matching)
        self.replaceValues(in: &self.collapsed, from: tree.collapsed, matchingId: matching)
        self.replaceNodes(in: &self.nodes, from: tree.nodes, matchingId: matching)
    }

    private func replaceValues<T>(in dictionary: inout [CollectionIdentifier: T], from newDictionary: [CollectionIdentifier: T], matchingId: (CollectionIdentifier) -> Bool) {
        // Remove all values matching id
        for key in dictionary.keys {
            guard matchingId(key) else { continue }
            dictionary[key] = nil
        }

        // Move all values from new dictionary to original
        for (key, value) in newDictionary {
            dictionary[key] = value
        }
    }

    private func replaceNodes(in array: inout [Node], from newArray: [Node], matchingId: (CollectionIdentifier) -> Bool) {
        var startIndex = -1
        var endIndex = -1

        for (idx, node) in array.enumerated() {
            if startIndex == -1 {
                if matchingId(node.identifier) {
                    startIndex = idx
                }
            } else if endIndex == -1 {
                if !matchingId(node.identifier) {
                    endIndex = idx
                    break
                }
            }
        }

        if startIndex == -1 {
            // No object of given type found, insert after .all
            array.insert(contentsOf: newArray, at: 1)
            return
        }

        if endIndex == -1 { // last cell was of the same type, so endIndex is at the end
            endIndex = array.count
        }

        array.remove(atOffsets: IndexSet(integersIn: startIndex..<endIndex))
        array.insert(contentsOf: newArray, at: startIndex)
    }
}

// MARK: - Diffable Data Source

extension CollectionTree {
    private func add<T>(nodes: [Node], to parent: T?, in snapshot: inout NSDiffableDataSourceSectionSnapshot<T>, allCollections: [CollectionIdentifier: T]) {
        guard !nodes.isEmpty else { return }

        let collections = nodes.map({ allCollections[$0.identifier] })
        snapshot.append(collections.compactMap({ $0 }), to: parent)

        for (idx, collection) in collections.enumerated() {
            guard let collection = collection else { continue }
            let node = nodes[idx]
            self.add(nodes: node.children, to: collection, in: &snapshot, allCollections: allCollections)
        }
    }

    private func addMapped<T, R>(mapping: (R) -> T, nodes: [Node], to parent: T?, in snapshot: inout NSDiffableDataSourceSectionSnapshot<T>, allCollections: [CollectionIdentifier: R]) {
        guard !nodes.isEmpty else { return }

        let collections = nodes.map({ allCollections[$0.identifier] })
        snapshot.append(collections.compactMap({ $0 }).map(mapping), to: parent)

        for (idx, collection) in collections.enumerated() {
            guard let collection = collection else { continue }
            let node = nodes[idx]
            self.addMapped(mapping: mapping, nodes: node.children, to: mapping(collection), in: &snapshot, allCollections: allCollections)
        }
    }

    func createSnapshot(selectedId: CollectionIdentifier? = nil, collapseState: CollapseState = .basedOnDb) -> NSDiffableDataSourceSectionSnapshot<Collection> {
        var snapshot = NSDiffableDataSourceSectionSnapshot<Collection>()
        self.add(nodes: self.nodes, to: nil, in: &snapshot, allCollections: self.collections)
        self.apply(selectedId: selectedId, collapseState: collapseState, to: &snapshot)
        return snapshot
    }

    func createMappedSnapshot<T>(mapping: (Collection) -> T, parent: T? = nil) -> NSDiffableDataSourceSectionSnapshot<T> {
        var snapshot = NSDiffableDataSourceSectionSnapshot<T>()
        if let parent = parent {
            snapshot.append([parent], to: nil)
        }
        self.addMapped(mapping: mapping, nodes: self.nodes, to: parent, in: &snapshot, allCollections: self.collections)
        return snapshot
    }

    private func apply(selectedId: CollectionIdentifier?, collapseState: CollapseState, to snapshot: inout NSDiffableDataSourceSectionSnapshot<Collection>) {
        let expandParents: (CollectionIdentifier , inout NSDiffableDataSourceSectionSnapshot<Collection>) -> Void = { identifier, snapshot in
            let parents = self.parentChain(for: identifier)
            if !parents.isEmpty {
                snapshot.expand(parents)
            }
        }

        switch collapseState {
        case .expandedAll:
            snapshot.expand(snapshot.items)
        case .collapsedAll:
            snapshot.collapse(snapshot.items)
            if let identifier = selectedId {
                expandParents(identifier, &snapshot)
            }
        case .basedOnDb:
            let (collapsed, expanded) = self.separateExpandedFromCollapsed(collections: snapshot.items, collapsedState: self.collapsed)
            snapshot.collapse(collapsed)
            snapshot.expand(expanded)
            if let identifier = selectedId {
                expandParents(identifier, &snapshot)
            }
        }
    }

    private func parentChain(for identifier: CollectionIdentifier, parents: [Collection] = []) -> [Collection] {
        guard let node = self.firstNode(with: identifier, in: self.nodes), let parentId = node.parent, let parentCollection = self.collections[parentId] else { return parents }
        return self.parentChain(for: parentId, parents: [parentCollection] + parents)
    }

    private func separateExpandedFromCollapsed(collections: [Collection], collapsedState: [CollectionIdentifier: Bool]) -> (collapsed: [Collection], expanded: [Collection]) {
        var collapsed: [Collection] = []
        var expanded: [Collection] = []

        for collection in collections {
            let isCollapsed = collapsedState[collection.identifier] ?? true
            if isCollapsed {
                collapsed.append(collection)
            } else {
                expanded.append(collection)
            }
        }

        return (collapsed, expanded)
    }

    func createSearchSnapshot(collapseState: CollapseState = .expandedAll) -> NSDiffableDataSourceSectionSnapshot<SearchableCollection> {
        var snapshot = NSDiffableDataSourceSectionSnapshot<SearchableCollection>()
        self.add(nodes: self.nodes, to: nil, in: &snapshot, allCollections: self.filtered)
        snapshot.expand(snapshot.items)
        return snapshot
    }

    func createMappedSearchSnapshot<T>(mapping: (SearchableCollection) -> T, parent: T? = nil) -> NSDiffableDataSourceSectionSnapshot<T> {
        var snapshot = NSDiffableDataSourceSectionSnapshot<T>()
        if let parent = parent {
            snapshot.append([parent], to: nil)
        }
        self.addMapped(mapping: mapping, nodes: self.nodes, to: parent, in: &snapshot, allCollections: self.filtered)
        return snapshot
    }
}

// MARK: - Search

extension CollectionTree {
    func searchableCollection(for identifier: CollectionIdentifier) -> SearchableCollection? {
        return self.filtered[identifier]
    }

    func search(for term: String) {
        var filtered: [CollectionIdentifier: SearchableCollection] = [:]
        self.add(nodes: self.nodes, ifTheyContain: term, to: &filtered, allCollections: self.collections)
        self.filtered = filtered
    }

    @discardableResult
    private func add(nodes: [Node], ifTheyContain text: String, to filtered: inout [CollectionIdentifier: SearchableCollection], allCollections: [CollectionIdentifier: Collection]) -> Bool {
        var containsText = false

        for node in nodes {
            guard !node.identifier.isCustom, let collection = allCollections[node.identifier] else { continue }

            if collection.name.localizedCaseInsensitiveContains(text) {
                containsText = true
                filtered[node.identifier] = SearchableCollection(isActive: true, collection: collection)
            }

            guard !node.children.isEmpty else { continue }

            let childrenContainText = self.add(nodes: node.children, ifTheyContain: text, to: &filtered, allCollections: allCollections)
            if !containsText && childrenContainText {
                filtered[node.identifier] = SearchableCollection(isActive: false, collection: collection)
                containsText = true
            }
        }

        return containsText
    }

    func cancelSearch() {
        self.filtered = [:]
    }
}
