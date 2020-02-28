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
    case startSync
    case cancelSync
    case logout
    case startObservingSyncChanges
}
