//
//  FullSyncDebuggingState.swift
//  Zotero
//
//  Created by Michal Rentka on 26.03.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct FullSyncDebuggingState: ViewModelState {
    var syncTypeInProgress: SyncController.Kind?

    init(syncTypeInProgress: SyncController.Kind?) {
        self.syncTypeInProgress = syncTypeInProgress
    }

    func cleanup() {}
}
