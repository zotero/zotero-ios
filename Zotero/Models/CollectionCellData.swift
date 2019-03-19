//
//  CollectionCellData.swift
//  Zotero
//
//  Created by Michal Rentka on 19/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct CollectionCellData {
    enum DataType {
        case collection(Bool) // hasChildren
        case search
        case custom(CustomType)
    }

    enum CustomType {
        case all, trash, publications
    }

    let type: CollectionCellData.DataType
    let key: String
    let name: String
    let level: Int

    init(object: RCollection, level: Int) {
        self.type = .collection(!object.children.isEmpty)
        self.key = object.key
        self.name = object.name
        self.level = level
    }

    init(object: RSearch) {
        self.type = .search
        self.key = object.key
        self.name = object.name
        self.level = 0
    }

    init(custom type: CustomType) {
        self.type = .custom(type)
        self.key = ""
        self.level = 0
        switch type {
        case .all:
            self.name = "All Items"
        case .publications:
            self.name = "My Publications"
        case .trash:
            self.name = "Trash"
        }
    }
}

extension CollectionCellData {
    static func createCells(from searches: Results<RSearch>) -> [CollectionCellData] {
        return searches.map(CollectionCellData.init)
    }

    static func createCells(from collections: Results<RCollection>) -> [CollectionCellData] {
        return CollectionCellData.cells(for: collections, parentKey: nil, level: 0)
    }

    private static func cells(for results: Results<RCollection>, parentKey: String?, level: Int) -> [CollectionCellData] {
        var filteredResults: Results<RCollection>
        if let key = parentKey {
            filteredResults = results.filter("parent.key = %@", key)
        } else {
            filteredResults = results.filter("parent == nil")
        }

        guard !filteredResults.isEmpty else { return [] }

        filteredResults = filteredResults.sorted(by: [SortDescriptor(keyPath: "name"),
                                                      SortDescriptor(keyPath: "key")])

        var cells: [CollectionCellData] = []
        for rCollection in filteredResults {
            let collection = CollectionCellData(object: rCollection, level: level)
            cells.append(collection)

            if rCollection.children.count > 0 {
                cells.append(contentsOf: CollectionCellData.cells(for: results,
                                                                  parentKey: collection.key,
                                                                  level: (level + 1)))
            }
        }
        return cells
    }
}
