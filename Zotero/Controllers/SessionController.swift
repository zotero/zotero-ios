//
//  SessionController.swift
//  Zotero
//
//  Created by Michal Rentka on 19/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

typealias SessionData = (userId: Int, apiToken: String)

struct DebugSessionConstants {
    #if DEBUG
    static let userId: Int? = 5487222
    static let apiToken: String? = "EG4p735j5tUhixLCtTg37WAs"
    #else
    static let userId: Int? = nil
    static let apiToken: String? = nil
    #endif
}

class SessionController: ObservableObject {
    @Published var sessionData: SessionData?
    @Published var isLoggedIn: Bool

    private let defaults: Defaults
    private let secureStorage: SecureStorage

    init(secureStorage: SecureStorage) {
        let defaults = Defaults.shared

        self.defaults = defaults
        self.secureStorage = secureStorage

        var apiToken = secureStorage.apiToken
        var userId = defaults.userId

        if (apiToken == nil || userId == 0),
           let debugUserId = DebugSessionConstants.userId,
           let debugApiToken = DebugSessionConstants.apiToken {
            apiToken = debugApiToken
            userId = debugUserId
            secureStorage.apiToken = debugApiToken
            defaults.userId = debugUserId
        }

        if let token = apiToken, userId > 0 {
            self.sessionData = (userId, token)
            self.isLoggedIn = true
        } else {
            self.sessionData = nil
            self.isLoggedIn = false
        }
    }

    func register(userId: Int, username: String, apiToken: String) {
        Defaults.shared.userId = userId
        Defaults.shared.username = username
        self.secureStorage.apiToken = apiToken

        self.set(data: (userId, apiToken))
    }

    func reset() {
        Defaults.shared.reset()
        self.secureStorage.apiToken = nil

        self.set(data: nil)
    }

    private func set(data: SessionData?) {
        // Order of these updates needs to be kept! We update sessionData first, so that UserControllers are updated. Then isLoggedIn is updated
        // and with it a proper screen is shown in AppDelegate.
        self.sessionData = data
        self.isLoggedIn = data != nil
    }
}
