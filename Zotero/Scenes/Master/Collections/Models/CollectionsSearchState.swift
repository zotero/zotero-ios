//
//  CollectionsSearchState.swift
//  Zotero
//
//  Created by Michal Rentka on 05/08/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CollectionsSearchState: ViewModelState {
    let collectionTree: CollectionTree

    init(collectionsTree: CollectionTree) {
        self.collectionTree = collectionsTree
    }

    mutating func cleanup() {}
}
