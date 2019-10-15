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

    var state: State {
        willSet {
            self.objectWillChange.send()
        }
    }
    // SWIFTUI BUG: should be defined by default, but bugged in current version
    let objectWillChange: ObservableObjectPublisher

    init() {
        self.objectWillChange = ObservableObjectPublisher()
        self.state = State()
    }
}
