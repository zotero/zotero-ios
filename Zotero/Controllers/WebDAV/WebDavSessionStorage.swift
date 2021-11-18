//
//  WebDavSessionStorage.swift
//  Zotero
//
//  Created by Michal Rentka on 05.10.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import CocoaLumberjackSwift
import Foundation

protocol WebDavSessionStorage: AnyObject {
    var isEnabled: Bool { get set }
    var isVerified: Bool { get set }
    var username: String { get set }
    var url: String { get set }
    var scheme: WebDavScheme { get set }
    var password: String { get set }

    func createToken() throws -> String
}

final class SecureWebDavSessionStorage: WebDavSessionStorage {
    private unowned let secureStorage: SecureStorage

    init(secureStorage: SecureStorage) {
        self.secureStorage = secureStorage
    }

    var isEnabled: Bool {
        get {
            return Defaults.shared.webDavEnabled
        }

        set {
            Defaults.shared.webDavEnabled = newValue
        }
    }

    var isVerified: Bool {
        get {
            return Defaults.shared.webDavVerified
        }

        set {
            Defaults.shared.webDavVerified = newValue
        }
    }

    var username: String {
        get {
            return Defaults.shared.webDavUsername ?? ""
        }

        set {
            Defaults.shared.webDavUsername = newValue.isEmpty ? nil : newValue
        }
    }

    var url: String {
        get {
            return Defaults.shared.webDavUrl ?? ""
        }

        set {
            Defaults.shared.webDavUrl = newValue.isEmpty ? nil : newValue
        }
    }

    var scheme: WebDavScheme {
        get {
            return Defaults.shared.webDavScheme
        }

        set {
            Defaults.shared.webDavScheme = newValue
        }
    }

    var password: String {
        get {
            return self.secureStorage.webDavPassword ?? ""
        }

        set {
            self.secureStorage.webDavPassword = newValue.isEmpty ? nil : newValue
        }
    }

    func createToken() throws -> String {
        let username = self.username
        guard !username.isEmpty else {
            DDLogError("WebDavSessionStorage: username not found")
            throw WebDavError.Verification.noUsername
        }
        let password = self.password
        guard !password.isEmpty else {
            DDLogError("WebDavSessionStorage: password not found")
            throw WebDavError.Verification.noPassword
        }

        let token = "\(username):\(password)".data(using: .utf8).flatMap({ $0.base64EncodedString(options: .endLineWithLineFeed) }) ?? ""
        return "Basic \(token)"
    }
}
