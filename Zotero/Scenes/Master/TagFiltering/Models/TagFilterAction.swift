//
//  TagFilterAction.swift
//  Zotero
//
//  Created by Michal Rentka on 22.03.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum TagFilterAction {
    case load(libraryId: LibraryIdentifier, collectionId: CollectionIdentifier, clearSelection: Bool)
    case select(String)
    case deselect(String)
    case search(String)
    case add(String)
}
