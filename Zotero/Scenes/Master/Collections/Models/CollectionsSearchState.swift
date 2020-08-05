//
//  CollectionsSearchState.swift
//  Zotero
//
//  Created by Michal Rentka on 05/08/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CollectionsSearchState: ViewModelState {
    let collections: [SearchableCollection]
    var filtered: [SearchableCollection]

    init(collections: [SearchableCollection]) {
        self.collections = collections
        self.filtered = []
    }

    mutating func cleanup() {}
}
