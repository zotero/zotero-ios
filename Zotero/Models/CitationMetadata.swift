//
//  CitationMetadata.swift
//  Zotero
//
//  Created by Michal Rentka on 04.09.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct CitationMetadata {
    let annotationKey: String
    let documentKey: String
    let libraryId: LibraryIdentifier
    let locator: UInt
}
