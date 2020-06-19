//
//  AttachmentFileDeletedNotification.swift
//  Zotero
//
//  Created by Michal Rentka on 12/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum AttachmentFileDeletedNotification {
    case individual(key: String, parentKey: String?, libraryId: LibraryIdentifier)
    case library(LibraryIdentifier)
    case all
}
