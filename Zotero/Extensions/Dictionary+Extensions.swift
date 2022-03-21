//
//  Dictionary+CaseInsensitiveKeyCheck.swift
//  Zotero
//
//  Created by Michal Rentka on 21.03.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

extension Dictionary where Key == AnyHashable {
    func caseInsensitiveContains(key: String) -> Bool {
        guard let stringDictionary = self as? [String: Value] else {
            return self[key] != nil
        }
        return stringDictionary.caseInsensitiveContains(key: key)
    }

    func value(forCaseInsensitive key: String) -> Value? {
        guard let stringDictionary = self as? [String: Value] else {
            return self[key]
        }
        return stringDictionary.value(forCaseInsensitive: key)
    }
}

extension Dictionary where Key == String {
    func caseInsensitiveContains(key: String) -> Bool {
        for _key in self.keys {
            if _key.lowercased() == key.lowercased() {
                return true
            }
        }
        return false
    }

    func value(forCaseInsensitive key: String) -> Value? {
        for (_key, value) in self {
            if _key.lowercased() == key.lowercased() {
                return value
            }
        }
        return nil
    }
}
