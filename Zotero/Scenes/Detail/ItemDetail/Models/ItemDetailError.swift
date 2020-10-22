//
//  ItemDetailError.swift
//  Zotero
//
//  Created by Michal Rentka on 18/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum ItemDetailError: Error, Equatable, Hashable {
    case schemaNotInitialized, typeNotSupported, libraryNotAssigned,
         contentTypeUnknown, userMissing, downloadError, unknown,
         cantStoreChanges
    case fileNotCopied(Int)
    case droppedFields([String])
    case cantUnzipSnapshot
}
