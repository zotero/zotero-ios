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
    case collapseAll
    case deleteCollection(String)
    case deleteSearch(String)
    case emptyTrash
    case expandAll
    case loadData
    case startEditing(CollectionsState.EditingType)
    case select(CollectionIdentifier)
    case toggleCollapsed(Collection)
}
