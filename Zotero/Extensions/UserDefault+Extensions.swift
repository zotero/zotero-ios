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
struct UserDefault<T: Equatable> {
    let key: String
    let defaultValue: T
    private let defaults: UserDefaults
    let didChangeNotificationName: Notification.Name?

    init(key: String, defaultValue: T, defaults: UserDefaults = UserDefaults.zotero, didChangeNotificationName: Notification.Name? = nil) {
        self.key = key
        self.defaultValue = defaultValue
        self.defaults = defaults
        self.didChangeNotificationName = didChangeNotificationName
    }

    var wrappedValue: T {
        get {
            return defaults.object(forKey: self.key) as? T ?? self.defaultValue
        }

        set {
            let didChange = newValue != wrappedValue
            defaults.set(newValue, forKey: self.key)
            guard didChange, let didChangeNotificationName else { return }
            // Notification is posted asynchronously, otherwise another access to the same property before set finishes, will trigger a simultaneous access during modification error.
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: didChangeNotificationName, object: newValue)
            }
        }
    }
}

@propertyWrapper
struct OptionalUserDefault<T> {
    let key: String
    private let defaults: UserDefaults

    init(key: String, defaults: UserDefaults = UserDefaults.zotero) {
        self.key = key
        self.defaults = defaults
    }

    var wrappedValue: T? {
        get {
            return self.defaults.object(forKey: self.key) as? T
        }

        set {
            self.defaults.set(newValue, forKey: self.key)
        }
    }
}

@propertyWrapper
struct CodableUserDefault<T: Codable> {
    let key: String
    let defaultValue: T
    let encoder: JSONEncoder
    let decoder: JSONDecoder
    private let defaults: UserDefaults

    init(key: String, defaultValue: T, encoder: JSONEncoder, decoder: JSONDecoder, defaults: UserDefaults = UserDefaults.zotero) {
        self.key = key
        self.defaultValue = defaultValue
        self.encoder = encoder
        self.decoder = decoder
        self.defaults = defaults
    }

    var wrappedValue: T {
        get {
            let data = self.defaults.data(forKey: self.key)
            return data.flatMap({ try? self.decoder.decode(T.self, from: $0) }) ?? self.defaultValue
        }

        set {
            guard let data = try? self.encoder.encode(newValue) else { return }
            self.defaults.setValue(data, forKey: self.key)
        }
    }
}
