//
//  ItemDetailError.swift
//  Zotero
//
//  Created by Michal Rentka on 18/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum ItemDetailError: Error, Equatable, Hashable {
    enum AttachmentAddError: Error, Equatable, Hashable {
        case couldNotMoveFromSource([String])
        case someFailedCreation([String])
        case allFailedCreation
    }

    case typeNotSupported(String)
    case cantStoreChanges
    case droppedFields([String])
    case cantCreateData
    case cantTrashItem
    case cantSaveNote
    case cantAddAttachments(AttachmentAddError)
    case cantSaveTags
    case cantRemoveItem
    case cantRemoveParent
    case cantRemoveCollection
}
