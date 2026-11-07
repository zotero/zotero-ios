//
//  ItemsError.swift
//  Zotero
//
//  Created by Michal Rentka on 21/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum ItemsError: Error, Equatable {
    enum AttachmentLoading: Equatable {
        case couldNotSave
        case someFailed([String])
    }

    case dataLoading
    case deletion
    case deletionFromCollection
    case deletionFromRecentlyRead
    case collectionAssignment
    case itemMove
    case noteSaving
    case attachmentAdding(AttachmentLoading)
    case duplicationLoading
}
