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

    static func collections(from collections: Results<RCollection>) -> [Collection] {
        return createCollections(from: collections, parentKey: nil, level: 0)
    }

    private static func createCollections(from results: Results<RCollection>, parentKey: String?, level: Int) -> [Collection] {
        var filteredResults: Results<RCollection>
        if let key = parentKey {
            filteredResults = results.filter("parent.key = %@", key)
        } else {
            filteredResults = results.filter("parent == nil")
        }

        guard !filteredResults.isEmpty else { return [] }

        filteredResults = filteredResults.sorted(by: [SortDescriptor(keyPath: "name"),
                                                      SortDescriptor(keyPath: "key")])

        var cells: [Collection] = []
        for rCollection in filteredResults {
            let collection = Collection(object: rCollection, level: level)
            cells.append(collection)

            if rCollection.children.count > 0 {
                cells.append(contentsOf: createCollections(from: results,
                                                           parentKey: collection.key,
                                                           level: (level + 1)))
            }
        }
        return cells
    }
}
