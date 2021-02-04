//
//  SecureStorage.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import KeychainSwift

protocol SecureStorage: class {
    var apiToken: String? { get set }
}

final class KeychainSecureStorage: SecureStorage {
    private struct Keys {
        static let apiToken = "api_token_key"
    }

    private let keychain: KeychainSwift

    init() {
        self.keychain = KeychainSwift()
        self.keychain.accessGroup = AppGroup.identifier
    }

    var apiToken: String? {
        get {
            return self.keychain.get(Keys.apiToken)
        }

        set {
            if let value = newValue {
                self.keychain.set(value, forKey: Keys.apiToken)
            } else {
                self.keychain.delete(Keys.apiToken)
            }
        }
    }
}
