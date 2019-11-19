//
//  SessionController.swift
//  Zotero
//
//  Created by Michal Rentka on 19/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import Foundation

typealias SessionData = (userId: Int, apiToken: String) // UserId, ApiToken
typealias SessionNotificationData = (userId: Int, username: String, apiToken: String) // UserId, Username, ApiToken

struct DebugSessionConstants {
    static let userId: Int? = 5487222//113123
    static let apiToken: String? = "EG4p735j5tUhixLCtTg37WAs"//"jVvCcLimmkx4SeUD3ET4Xplf"
}

class SessionController: ObservableObject {
    @Published var sessionData: SessionData?
    @Published var isLoggedIn: Bool

    private let defaults: Defaults
    private let secureStorage: SecureStorage

    private var notificationCancellable: AnyCancellable?

    init(secureStorage: SecureStorage) {
        let defaults = Defaults.shared

        self.defaults = defaults
        self.secureStorage = secureStorage

        if let debugUserId = DebugSessionConstants.userId,
           let debugApiToken = DebugSessionConstants.apiToken {
            secureStorage.apiToken = debugApiToken
            defaults.userId = debugUserId
        }

        if let token = secureStorage.apiToken, defaults.userId > 0 {
            self.sessionData = (defaults.userId, token)
            self.isLoggedIn = true
        } else {
            self.sessionData = nil
            self.isLoggedIn = false
        }

        self.notificationCancellable = NotificationCenter.default
                                                         .publisher(for: .sessionChanged)
                                                         .sink { [weak self] notification in
                                                             self?.sessionChanged(to: (notification.object as? SessionNotificationData))
                                                         }
    }

    private func sessionChanged(to data: SessionNotificationData?) {
        // Set session data to appropriate storages
        if let (userId, username, apiToken) = data {
            Defaults.shared.userId = userId
            Defaults.shared.username = username
            self.secureStorage.apiToken = apiToken
        } else {
            // User logged out, reset user defaults
            Defaults.shared.reset()
            self.secureStorage.apiToken = nil
        }

        // Order of these updates needs to be kept! We update sessionData first, so that UserControllers are updated. Then isLoggedIn is updated
        // and with it a proper screen is shown in AppDelegate.
        self.sessionData = data.flatMap { ($0.0, $0.2) }
        self.isLoggedIn = data != nil
    }
}
