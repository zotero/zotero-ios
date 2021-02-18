//
//  RPageIndex.swift
//  Zotero
//
//  Created by Michal Rentka on 18.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct RPageIndexChanges: OptionSet {
    typealias RawValue = Int16

    let rawValue: Int16

    init(rawValue: Int16) {
        self.rawValue = rawValue
    }
}

extension RPageIndexChanges {
    static let index = RPageIndexChanges(rawValue: 1 << 0)
}

final class RPageIndex: Object {
    @objc dynamic var key: String = ""
    @objc dynamic var index: Int = 0
    @objc dynamic var changed: Bool = false

    let customLibraryKey = RealmOptional<Int>()
    let groupKey = RealmOptional<Int>()

    // MARK: - Sync data
    /// Indicates local version of object
    @objc dynamic var version: Int = 0
    /// State which indicates whether object is synced with backend data, see ObjectSyncState for more info
    @objc dynamic var rawSyncState: Int = 0
    /// Date when last sync attempt was performed on this object
    @objc dynamic var lastSyncDate: Date = Date(timeIntervalSince1970: 0)
    /// Number of retries for sync of this object
    @objc dynamic var syncRetries: Int = 0
    /// Raw value for OptionSet of changes for this object, indicates which local changes need to be synced to backend
    @objc dynamic var rawChangedFields: Int16 = 0
    /// Raw value for `UpdatableChangeType`, indicates whether current update of item has been made by user or sync process.
    @objc dynamic var rawChangeType: Int = 0

    // MARK: - Object properties

    override class func indexedProperties() -> [String] {
        return ["version", "key"]
    }

    // MARK: - Sync properties

    var changedFields: RPageIndexChanges {
        get {
            return RPageIndexChanges(rawValue: self.rawChangedFields)
        }

        set {
            self.rawChangedFields = newValue.rawValue
        }
    }
}
