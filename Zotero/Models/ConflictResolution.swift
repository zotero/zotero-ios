//
//  ConflictResolution.swift
//  Zotero
//
//  Created by Michal Rentka on 03/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum ConflictResolution {
    case deleteGroup(Int)
    case markGroupAsLocalOnly(Int)
    case revertGroupChanges(LibraryIdentifier)
    case keepGroupChanges(LibraryIdentifier)
    case revertGroupFiles(LibraryIdentifier)
    case skipGroup(LibraryIdentifier)
    case remoteDeletionOfActiveObject(libraryId: LibraryIdentifier, toDeleteCollections: [String], toRestoreCollections: [String],
                                      toDeleteItems: [String], toRestoreItems: [String], searches: [String], tags: [String])
    case remoteDeletionOfChangedItem(libraryId: LibraryIdentifier, toDelete: [String], toRestore: [String])
}
