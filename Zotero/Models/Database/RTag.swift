//
//  RTag.swift
//  Zotero
//
//  Created by Michal Rentka on 25/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct RTagChanges: OptionSet {
    typealias RawValue = Int16

    let rawValue: Int16

    init(rawValue: Int16) {
        self.rawValue = rawValue
    }
}

extension RTagChanges {
    static let name = RTagChanges(rawValue: 1 << 0)
    static let color = RTagChanges(rawValue: 1 << 1)
    static let all: RTagChanges = [.name, .color]
}

final class RTag: Object {
    @objc dynamic var name: String = ""
    @objc dynamic var color: String = ""
    let customLibraryKey = RealmOptional<Int>()
    let groupKey = RealmOptional<Int>()
    let items: List<RItem> = List()

    // MARK: - Sync data

    /// Raw value for OptionSet of changes for this object, indicates which local changes need to be synced to backend
    @objc dynamic var rawChangedFields: Int16 = 0
    /// Raw value for `UpdatableChangeType`, indicates whether current update of item has been made by user or sync process.
    @objc dynamic var rawChangeType: Int = 0

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

    var changedFields: RTagChanges {
        get {
            return RTagChanges(rawValue: self.rawChangedFields)
        }

        set {
            self.rawChangedFields = newValue.rawValue
        }
    }
}
