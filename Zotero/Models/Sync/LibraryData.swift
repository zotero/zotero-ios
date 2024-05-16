//
//  LibraryData.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct LibraryData {
    let identifier: LibraryIdentifier
    let name: String
    let versions: Versions
    let canEditMetadata: Bool
    let canEditFiles: Bool
    let updates: [WriteBatch]
    let deletions: [DeleteBatch]
    let hasUpload: Bool
    let hasWebDavDeletions: Bool
    let fileSyncType: LibraryFileSyncType
}
