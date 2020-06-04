//
//  SettingsState.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct SettingsState: ViewModelState {
    var askForSyncPermission: Bool
    var showCollectionItemCount: Bool
    var isSyncing: Bool
    var isLogging: Bool
    var lastTranslatorUpdate: Date
    var isUpdatingTranslators: Bool
    var logoutAlertVisible: Bool
    var libraries: [Library]
    var storageData: [LibraryIdentifier: DirectoryData]
    var totalStorageData: DirectoryData?
    var showDeleteAllQuestion: Bool
    var showDeleteLibraryQuestion: Library?

    init(isSyncing: Bool, isLogging: Bool, isUpdatingTranslators: Bool, lastTranslatorUpdate: Date) {
        self.isSyncing = isSyncing
        self.isLogging = isLogging
        self.lastTranslatorUpdate = lastTranslatorUpdate
        self.isUpdatingTranslators = isUpdatingTranslators
        self.askForSyncPermission = Defaults.shared.askForSyncPermission
        self.showCollectionItemCount = Defaults.shared.showCollectionItemCount
        self.logoutAlertVisible = false
        self.libraries = []
        self.storageData = [:]
        self.showDeleteAllQuestion = false
    }

    func cleanup() {}
}
