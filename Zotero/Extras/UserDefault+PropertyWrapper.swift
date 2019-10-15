//
//  UserDefault+PropertyWrapper.swift
//  Zotero
//
//  Created by Michal Rentka on 15/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

@propertyWrapper
struct UserDefault<T> {
    let key: String
    let defaultValue: T

    var wrappedValue: T {
        get {
            return UserDefaults.standard.object(forKey: self.key) as? T ?? self.defaultValue
        }

        set {
            UserDefaults.standard.set(newValue, forKey: self.key)
        }
    }
}
