//
//  RTag.swift
//  Zotero
//
//  Created by Michal Rentka on 25/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

final class RTag: Object {
    enum Kind: Int {
        case automatic = 1
        case manual = 0
    }

    @objc dynamic var name: String = ""
    @objc dynamic var color: String = ""
    @objc dynamic var rawType: Int = 0
    @objc dynamic var item: RItem?
    let customLibraryKey = RealmOptional<Int>()
    let groupKey = RealmOptional<Int>()

    var type: Kind {
        get {
            return Kind(rawValue: self.rawType) ?? .manual
        }

        set {
            self.rawType = newValue.rawValue
        }
    }

    // MARK: - Object properties

    override class func indexedProperties() -> [String] {
        return ["name"]
    }

    // MARK: - Sync properties

    var libraryId: LibraryIdentifier? {
        get {
            if let key = self.customLibraryKey.value, let type = RCustomLibraryType(rawValue: key) {
                return .custom(type)
            }
            if let key = self.groupKey.value {
                return .group(key)
            }
            return nil
        }

        set {
            guard let identifier = newValue else {
                self.groupKey.value = nil
                self.customLibraryKey.value = nil
                return
            }

            switch identifier {
            case .custom(let type):
                self.customLibraryKey.value = type.rawValue
            case .group(let id):
                self.groupKey.value = id
            }
        }
    }
}
