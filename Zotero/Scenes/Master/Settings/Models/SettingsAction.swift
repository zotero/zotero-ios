//
//  SettingsAction.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum SettingsAction {
    case cancelSync
    case connectToWebSocket
    case deleteAllDownloads
    case deleteDownloadsInLibrary(LibraryIdentifier)
    case disconnectFromWebSocket
    case loadStorageData
    case logout
    case resetTranslators
    case setAskForSyncPermission(Bool)
    case setIncludeTags(Bool)
    case setIncludeAttachment(Bool)
    case setLogoutAlertVisible(Bool)
    case setShowSubcollectionItems(Bool)
    case showDeleteAllQuestion(Bool)
    case showDeleteLibraryQuestion(Library?)
    case startImmediateLogging
    case startLoggingOnNextLaunch
    case startObserving
    case startSync
    case stopLogging
    case updateTranslators
}
