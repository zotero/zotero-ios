//
//  StorageSettingsState.swift
//  Zotero
//
//  Created by Michal Rentka on 11.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct StorageSettingsState: ViewModelState {
    var libraries: [Library]
    var storageData: [LibraryIdentifier: DirectoryData]
    var totalStorageData: DirectoryData

    init(storageData: [LibraryIdentifier: DirectoryData]? = nil) {
        self.storageData = storageData ?? [:]
        self.totalStorageData = DirectoryData(fileCount: 0, mbSize: 0)
        self.libraries = []
    }

    func cleanup() {}
}
