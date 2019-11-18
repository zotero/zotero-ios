//
//  UserDefaults.swift
//  Zotero
//
//  Created by Michal Rentka on 18/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

class Defaults {
    static let shared = Defaults()

    @UserDefault(key: "AskForSyncPermission", defaultValue: false)
    var askForSyncPermission: Bool

    @UserDefault(key: "username", defaultValue: "")
    var username: String

    @UserDefault(key: "userid", defaultValue: 0)
    var userId: Int

    func reset() {
        self.askForSyncPermission = false
        self.username = ""
        self.userId = 0
    }
}
