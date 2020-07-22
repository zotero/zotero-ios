//
//  CollectionsAction.swift
//  Zotero
//
//  Created by Michal Rentka on 24/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum CollectionsAction {
    case assignKeysToCollection([String], String)
    case deleteCollection(String)
    case deleteSearch(String)
    case startEditing(CollectionsState.EditingType)
    case select(Collection)
    case updateCollections([Collection])
    case loadData
    case search(String)
}
