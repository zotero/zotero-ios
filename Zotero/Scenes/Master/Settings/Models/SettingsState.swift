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
    var totalStorageData: DirectoryData
    var cacheData: DirectoryData
    var showDeleteAllQuestion: Bool
    var showDeleteLibraryQuestion: Library?
    var showDeleteCacheQuestion: Bool
    var websocketConnectionState: WebSocketController.ConnectionState

    init(isSyncing: Bool, isLogging: Bool, isUpdatingTranslators: Bool, lastTranslatorUpdate: Date, websocketConnectionState: WebSocketController.ConnectionState) {
        self.isSyncing = isSyncing
        self.isLogging = isLogging
        self.lastTranslatorUpdate = lastTranslatorUpdate
        self.isUpdatingTranslators = isUpdatingTranslators
        self.totalStorageData = DirectoryData(fileCount: 0, mbSize: 0)
        self.cacheData = DirectoryData(fileCount: 0, mbSize: 0)
        self.websocketConnectionState = websocketConnectionState
        self.askForSyncPermission = Defaults.shared.askForSyncPermission
        self.showCollectionItemCount = Defaults.shared.showCollectionItemCount
        self.logoutAlertVisible = false
        self.libraries = []
        self.storageData = [:]
        self.showDeleteAllQuestion = false
        self.showDeleteCacheQuestion = false
    }

    func cleanup() {}
}
