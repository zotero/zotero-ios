//
//  SettingsStore.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

class SettingsStore: ObservableObject {
    struct State {
        @UserDefault(key: "AskForSyncPermission", defaultValue: false)
        var askForSyncPermission: Bool
    }

    @Published var state: State

    init() {
        self.state = State()
    }
}
