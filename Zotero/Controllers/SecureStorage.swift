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

    func reset()
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

    func reset() {
        self.apiToken = nil
        self.webDavPassword = nil
    }
}

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
                self.keychain.set(value, forKey: self.key)
            } else {
                self.keychain.delete(self.key)
            }
        }
    }
}
