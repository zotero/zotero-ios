//
//  UserDefault+PropertyWrapper.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

extension UserDefaults {
    static var zotero: UserDefaults {
        return UserDefaults(suiteName: AppGroup.identifier) ?? UserDefaults.standard
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
