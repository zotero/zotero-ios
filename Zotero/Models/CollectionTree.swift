//
//  CollectionTree.swift
//  Zotero
//
//  Created by Michal Rentka on 09.02.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

final class CollectionTree {
    struct Node {
        let identifier: CollectionIdentifier
        let children: [CollectionIdentifier]
    }

    let nodes: [Node]
    private var collections: [CollectionIdentifier: Collection]
    private var collapsed: [CollectionIdentifier: Bool]

    init(nodes: [Node], collections: [CollectionIdentifier: Collection], collapsed: [CollectionIdentifier: Bool]) {
        self.nodes = nodes
        self.collections = collections
        self.collapsed = collapsed
    }

    func collection(for identifier: CollectionIdentifier) -> Collection? {
        return self.collections[identifier]
    }

    func update(collection: Collection) {
        self.collections[collection.identifier] = collection
    }

    func isCollapsed(identifier: CollectionIdentifier) -> Bool {
        return self.collapsed[identifier] ?? false
    }

    func set(collapsed: Bool, to identifier: CollectionIdentifier) {
        self.collapsed[identifier] = collapsed
    }
}
