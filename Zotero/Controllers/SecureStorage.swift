//
//  SecureStorage.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import KeychainSwift

protocol SecureStorage: AnyObject {
    var apiToken: String? { get set }
    var webDavPassword: String? { get set }
    var lastResultCode: OSStatus { get }

    func reset()
    /// Stores values again with current accessibility, see `SecureString`. Needs the values to be readable.
    func updateAccessibilityIfNeeded()
}

final class KeychainSecureStorage: SecureStorage {
    private static let keychain: KeychainSwift = KeychainSecureStorage.createKeychain()

    private static func createKeychain() -> KeychainSwift {
        let keychain = KeychainSwift()
        keychain.accessGroup = AppGroup.identifier
        return keychain
    }

    @SecureString(key: "api_token_key", keychain: KeychainSecureStorage.keychain)
    var apiToken: String?
    @SecureString(key: "webDavPassword", keychain: KeychainSecureStorage.keychain)
    var webDavPassword: String?

    var lastResultCode: OSStatus {
        return KeychainSecureStorage.keychain.lastResultCode
    }

    func reset() {
        KeychainSecureStorage.keychain.clear()
    }

    func updateAccessibilityIfNeeded() {
        guard !Defaults.shared.didUpdateKeychainAccessibility else { return }
        // Setting values stores them with current accessibility.
        if let apiToken {
            self.apiToken = apiToken
        }
        if let webDavPassword {
            self.webDavPassword = webDavPassword
        }
        Defaults.shared.didUpdateKeychainAccessibility = true
    }
}

/// Values are accessible after the device is unlocked for the first time since restart, so that they can be read while it's
/// locked, e.g. when the app is launched by CarPlay or in background. Values stored before used the default
/// `.accessibleWhenUnlocked`, see `SecureStorage.updateAccessibilityIfNeeded()`.
@propertyWrapper
struct SecureString {
    let key: String
    private let keychain: KeychainSwift

    init(key: String, keychain: KeychainSwift) {
        self.key = key
        self.keychain = keychain
    }

    var wrappedValue: String? {
        get {
            return self.keychain.get(self.key)
        }

        set {
            if let value = newValue {
                self.keychain.set(value, forKey: self.key, withAccess: .accessibleAfterFirstUnlock)
            } else {
                self.keychain.delete(self.key)
            }
        }
    }
}
