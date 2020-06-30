//
//  UserDefault+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

extension UserDefaults {
    // MARK: - Custom defaults

    static var zotero: UserDefaults {
        return UserDefaults(suiteName: AppGroup.identifier) ?? UserDefaults.standard
    }

    // MARK: - Codable

    func object<T: Codable>(_ type: T.Type, with key: String, usingDecoder decoder: JSONDecoder = JSONDecoder()) -> T? {
        guard let data = self.value(forKey: key) as? Data else { return nil }
        return try? decoder.decode(type.self, from: data)
    }

    func set<T: Codable>(object: T, forKey key: String, usingEncoder encoder: JSONEncoder = JSONEncoder()) {
        let data = try? encoder.encode(object)
        self.set(data, forKey: key)
    }
}

@propertyWrapper
struct UserDefault<T> {
    let key: String
    let defaultValue: T

    var wrappedValue: T {
        get {
            return UserDefaults.zotero.object(forKey: self.key) as? T ?? self.defaultValue
        }

        set {
            UserDefaults.zotero.set(newValue, forKey: self.key)
        }
    }
}
