//
//  TrashAction.swift
//  Zotero
//
//  Created by Michal Rentka on 18.07.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum TrashAction {
    case assignItemsToCollections(items: Set<String>, collections: Set<String>)
    case deleteItems(Set<String>)
    case deleteItemsFromCollection(Set<String>)
    case deselectItem(TrashKey)
    case disableFilter(ItemsFilter)
    case emptyTrash
    case enableFilter(ItemsFilter)
    case loadData
    case moveItems(keys: Set<String>, toItemKey: String)
    case restoreItems(Set<String>)
    case search(String)
    case setSortField(ItemsSortType.Field)
    case setSortOrder(Bool)
    case selectItem(TrashKey)
    case startEditing
    case stopEditing
    case tagItem(itemKey: String, libraryId: LibraryIdentifier, tagNames: Set<String>)
    case toggleSelectionState
}
