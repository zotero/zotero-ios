//
//  SyncSettingsAction.swift
//  Zotero
//
//  Created by Michal Rentka on 06.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

enum SyncSettingsAction {
    case logout
    case setFileSyncType(SyncSettingsState.FileSyncType)
    case setScheme(WebDavScheme)
    case setUrl(String)
    case setUsername(String)
    case setPassword(String)
    case verify
    case cancelVerification
}
