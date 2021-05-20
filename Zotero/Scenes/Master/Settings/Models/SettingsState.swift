//
//  SettingsState.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct SettingsState: ViewModelState {
    var askForSyncPermission: Bool {
        get {
            return Defaults.shared.askForSyncPermission
        }

        set {
            Defaults.shared.askForSyncPermission = newValue
        }
    }
    var showSubcollectionItems: Bool {
        get {
            return Defaults.shared.showSubcollectionItems
        }

        set {
            Defaults.shared.showSubcollectionItems = newValue
        }
    }
    var isSyncing: Bool
    var isLogging: Bool
    var lastTranslatorUpdate: Date
    var isUpdatingTranslators: Bool
    var logoutAlertVisible: Bool
    var libraries: [Library]
    var storageData: [LibraryIdentifier: DirectoryData]
    var totalStorageData: DirectoryData
    var showDeleteAllQuestion: Bool
    var showDeleteLibraryQuestion: Library?
    var websocketConnectionState: WebSocketController.ConnectionState
    var includeTags: Bool {
        get {
            return Defaults.shared.shareExtensionIncludeTags
        }

        set {
            Defaults.shared.shareExtensionIncludeTags = newValue
        }
    }
    var includeAttachment: Bool {
        get {
            return Defaults.shared.shareExtensionIncludeAttachment
        }

        set {
            Defaults.shared.shareExtensionIncludeAttachment = newValue
        }
    }

    init(isSyncing: Bool, isLogging: Bool, isUpdatingTranslators: Bool, lastTranslatorUpdate: Date, websocketConnectionState: WebSocketController.ConnectionState) {
        self.isSyncing = isSyncing
        self.isLogging = isLogging
        self.lastTranslatorUpdate = lastTranslatorUpdate
        self.isUpdatingTranslators = isUpdatingTranslators
        self.totalStorageData = DirectoryData(fileCount: 0, mbSize: 0)
        self.websocketConnectionState = websocketConnectionState
        self.logoutAlertVisible = false
        self.libraries = []
        self.storageData = [:]
        self.showDeleteAllQuestion = false
    }

    init(storageData: [LibraryIdentifier: DirectoryData]) {
        self.storageData = storageData
        self.totalStorageData = DirectoryData(fileCount: 0, mbSize: 0)

        self.isSyncing = false
        self.isLogging = false
        self.lastTranslatorUpdate = Date()
        self.isUpdatingTranslators = false
        self.websocketConnectionState = .disconnected
        self.logoutAlertVisible = false
        self.libraries = []
        self.showDeleteAllQuestion = false
    }

    func cleanup() {}
}
