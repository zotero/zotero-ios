//
//  StorageSettingsAction.swift
//  Zotero
//
//  Created by Michal Rentka on 11.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum StorageSettingsAction {
    case loadData
    case deleteAll
    case deleteInLibrary(LibraryIdentifier)
    case setStoragePreference(AttachmentStoragePreference)
}
