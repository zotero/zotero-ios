//
//  TagFilterAction.swift
//  Zotero
//
//  Created by Michal Rentka on 22.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum TagFilterAction {
    case loadWithCollection(collectionId: CollectionIdentifier, libraryId: LibraryIdentifier, clearSelection: Bool)
    case loadWithKeys(itemKeys: Set<String>, libraryId: LibraryIdentifier, clearSelection: Bool)
    case select(String)
    case deselect(String)
    case search(String)
    case add(String)
    case setDisplayAll(Bool)
    case setShowAutomatic(Bool)
    case deselectAll
    case deleteAutomatic
}
