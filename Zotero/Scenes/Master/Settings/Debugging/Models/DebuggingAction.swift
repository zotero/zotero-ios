//
//  DebuggingAction.swift
//  Zotero
//
//  Created by Michal Rentka on 11.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum DebuggingAction {
    case startImmediateLogging
    case startLoggingOnNextLaunch
    case cancelLogging
    case stopLogging
    case exportDb
    case monitorIfNeeded
    case clearLogs
    case showLogs
    case showFullSyncDebugging
}
