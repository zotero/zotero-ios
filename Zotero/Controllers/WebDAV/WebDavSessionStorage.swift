//
//  WebDavSessionStorage.swift
//  Zotero
//
//  Created by Michal Rentka on 05.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

protocol WebDavSessionStorage: AnyObject {
    var username: String { get set }
    var url: String { get set }
    var scheme: WebDavScheme { get set }
    var password: String { get set }
}

final class SecureWebDavSessionStorage: WebDavSessionStorage {
    private unowned let secureStorage: SecureStorage

    init(secureStorage: SecureStorage) {
        self.secureStorage = secureStorage
    }

    var username: String {
        get {
            // TODO: - remove after test
            return "user"
//            return Defaults.shared.webDavUsername
        }

        set {
            Defaults.shared.webDavUsername = newValue
        }
    }

    var url: String {
        get {
            // TODO: - remove after test
            return "192.168.0.101:8080"
//            return Defaults.shared.webDavUrl
        }

        set {
            Defaults.shared.webDavUrl = newValue
        }
    }

    var scheme: WebDavScheme {
        get {
            // TODO: - remove after test
            return .http
//            return Defaults.shared.webDavScheme
        }

        set {
            Defaults.shared.webDavScheme = newValue
        }
    }

    var password: String {
        get {
            // TODO: - remove after test
            return "password"
//            return self.secureStorage.webDavPassword
        }

        set {
            self.secureStorage.webDavPassword = newValue
        }
    }
}
