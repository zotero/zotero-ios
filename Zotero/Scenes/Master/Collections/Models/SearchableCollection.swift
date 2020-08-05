//
//  SearchableCollection.swift
//  Zotero
//
//  Created by Michal Rentka on 23/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct SearchableCollection: Equatable, Hashable {
    let isActive: Bool
    let collection: Collection

    func isActive(_ isActive: Bool) -> Self {
        return SearchableCollection(isActive: isActive, collection: self.collection)
    }
}
