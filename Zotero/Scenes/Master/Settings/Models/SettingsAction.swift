//
//  SettingsAction.swift
//  Zotero
//
//  Created by Michal Rentka on 28/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum SettingsAction {
    case setAskForSyncPermission(Bool)
    case setShowCollectionItemCounts(Bool)
    case startSync
    case cancelSync
    case setLogoutAlertVisible(Bool)
    case logout
    case startObserving
    case startImmediateLogging
    case startLoggingOnNextLaunch
    case stopLogging
    case resetTranslators
    case updateTranslators
    case loadStorageData
    case deleteAllDownloads
    case deleteDownloadsInLibrary(LibraryIdentifier)
    case showDeleteAllQuestion(Bool)
    case showDeleteLibraryQuestion(Library?)
    case deleteCache
    case showDeleteCacheQuestion(Bool)
    case disconnectFromWebSocket
    case connectToWebSocket
    case setIncludeTags(Bool)
    case setIncludeAttachment(Bool)
}
