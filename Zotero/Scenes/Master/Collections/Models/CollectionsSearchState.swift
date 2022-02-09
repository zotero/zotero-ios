//
//  CollectionsSearchState.swift
//  Zotero
//
//  Created by Michal Rentka on 05/08/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CollectionsSearchState: ViewModelState {
    let collections: [CollectionIdentifier: Collection]
    let rootCollections: [CollectionIdentifier]
    let childCollections: [CollectionIdentifier: [CollectionIdentifier]]

    var filtered: [CollectionIdentifier: SearchableCollection]

    init(collections: [CollectionIdentifier: Collection], rootCollections: [CollectionIdentifier], childCollections: [CollectionIdentifier: [CollectionIdentifier]]) {
        self.collections = collections
        self.rootCollections = rootCollections
        self.childCollections = childCollections
        self.filtered = [:]
    }

    mutating func cleanup() {}
}
