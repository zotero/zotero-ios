//
//  Conflict.swift
//  Zotero
//
//  Created by Michal Rentka on 03/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum Conflict {
    case groupRemoved(groupId: Int, name: String)
    case groupMetadataWriteDenied(groupId: Int, name: String)
    case groupFileWriteDenied(groupId: Int, name: String)
    case objectsRemovedRemotely(libraryId: LibraryIdentifier, collections: [String], items: [String], searches: [String], tags: [String])
    case removedItemsHaveLocalChanges(keys: [(String, String)], libraryId: LibraryIdentifier)
}
