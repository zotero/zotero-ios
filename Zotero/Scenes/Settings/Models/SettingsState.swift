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
    var isWaitingOnTermination: Bool

    init(isSyncing: Bool, isLogging: Bool, isWaitingOnTermination: Bool) {
        self.isSyncing = isSyncing
        self.isLogging = isLogging
        self.isWaitingOnTermination = isWaitingOnTermination
        self.askForSyncPermission = Defaults.shared.askForSyncPermission
        self.showCollectionItemCount = Defaults.shared.showCollectionItemCount
    }

    func cleanup() {}
}
