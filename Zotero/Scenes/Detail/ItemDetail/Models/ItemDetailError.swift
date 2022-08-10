//
//  ItemDetailError.swift
//  Zotero
//
//  Created by Michal Rentka on 18/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum ItemDetailError: Error, Equatable, Hashable {
    case schemaNotInitialized
    case typeNotSupported
    case libraryNotAssigned
    case contentTypeUnknown
    case userMissing
    case downloadError
    case unknown
    case cantStoreChanges
    case fileNotCopied(Int)
    case droppedFields([String])
    case cantUnzipSnapshot
    case cantCreateData
    case cantTrashItem
}
