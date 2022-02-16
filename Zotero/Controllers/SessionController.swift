//
//  SessionController.swift
//  Zotero
//
//  Created by Michal Rentka on 19/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

typealias SessionData = (userId: Int, apiToken: String)

struct DebugSessionConstants {
    #if DEBUG
    static let userId: Int? = nil
    static let apiToken: String? = nil
    #else
    static let userId: Int? = nil
    static let apiToken: String? = nil
    #endif
}

final class SessionController: ObservableObject {
    enum Error: Swift.Error {
        case keychainNotAccessible(protectedDataAvailable: Bool, lastResultCode: OSStatus)
    }

    @Published var sessionData: SessionData?
    var isLoggedIn: Bool {
        return self.sessionData != nil
    }
    private(set) var isInitialized: Bool

    private let defaults: Defaults
    private let secureStorage: SecureStorage

    init(secureStorage: SecureStorage, defaults: Defaults) {
        self.defaults = defaults
        self.secureStorage = secureStorage
        self.isInitialized = false
    }

    func initializeSession() throws {
        var apiToken = self.secureStorage.apiToken
        var userId = self.defaults.userId

        if (apiToken == nil || userId == 0),
           let debugUserId = DebugSessionConstants.userId,
           let debugApiToken = DebugSessionConstants.apiToken {
            apiToken = debugApiToken
            userId = debugUserId
            self.secureStorage.apiToken = debugApiToken
            self.defaults.userId = debugUserId
        }

        if userId > 0 && apiToken == nil {
            #if MAINAPP
            let isAvailable = UIApplication.shared.isProtectedDataAvailable

            if isAvailable {
                // If protected data is available and api token can't be loaded anyway, set `isInitialized` to `true` so that login screen is shown to the user
                self.isInitialized = true
            }

            throw Error.keychainNotAccessible(protectedDataAvailable: isAvailable, lastResultCode: self.secureStorage.lastResultCode)
            #endif
        }

        self.isInitialized = true

        if let token = apiToken, userId > 0 {
            self.sessionData = (userId, token)
        } else {
            self.sessionData = nil
        }
    }

    func register(userId: Int, username: String, displayName: String, apiToken: String) {
        self.defaults.userId = userId
        self.defaults.username = username
        self.defaults.displayName = displayName
        self.secureStorage.apiToken = apiToken
        self.sessionData = (userId, apiToken)
        self.isInitialized = true
    }

    func reset() {
        self.defaults.reset()
        self.secureStorage.reset()
        self.sessionData = nil
    }
}
