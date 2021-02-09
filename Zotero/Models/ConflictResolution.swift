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
    case revertLibraryToOriginal(LibraryIdentifier)
    case markChangesAsResolved(LibraryIdentifier)
    case deleteObjects(libraryId: LibraryIdentifier, collections: [String], items: [String], searches: [String], tags: [String], version: Int)
}
