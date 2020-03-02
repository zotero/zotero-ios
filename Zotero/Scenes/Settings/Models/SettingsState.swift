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

    init(isSyncing: Bool) {
        self.isSyncing = isSyncing
        self.askForSyncPermission = Defaults.shared.askForSyncPermission
        self.showCollectionItemCount = Defaults.shared.showCollectionItemCount
    }

    func cleanup() {}
}
