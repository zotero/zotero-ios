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
    var host: String { get }
    var port: Int { get }
    var scheme: WebDavScheme { get set }
    var password: String { get set }
}

extension WebDavSessionStorage {
    var host: String {
        return url.split(separator: ":", maxSplits: 2).first.flatMap { String($0) } ?? ""
    }

    var port: Int {
        url.split(separator: ":", maxSplits: 2).last.flatMap { Int($0) } ?? 80
    }
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
}
