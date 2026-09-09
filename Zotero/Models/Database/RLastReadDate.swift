//
//  RLastReadDate.swift
//  Zotero
//
//  Created by Michal Rentka on 20.03.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct RLastReadDateChanges: OptionSet {
    typealias RawValue = Int16

    let rawValue: Int16

    init(rawValue: Int16) {
        self.rawValue = rawValue
    }
}

extension RLastReadDateChanges {
    static let date = RLastReadDateChanges(rawValue: 1 << 0)
}

final class RLastReadDate: Object {
    @Persisted(indexed: true) var key: String
    @Persisted var date: Date
    @Persisted var changed: Bool
    @Persisted var groupKey: Int?
    /// Indicates which local changes need to be synced to backend
    @Persisted var changes: List<RObjectChange>

    // MARK: - Sync data
    /// Indicates local version of object
    @Persisted(indexed: true) var version: Int
    /// State which indicates whether object is synced with backend data, see ObjectSyncState for more info
    @Persisted var syncState: ObjectSyncState
    /// Date when last sync attempt was performed on this object
    @Persisted var lastSyncDate: Date
    /// Number of retries for sync of this object
    @Persisted var syncRetries: Int
    /// Raw value for `UpdatableChangeType`, indicates whether current update of item has been made by user or sync process.
    @Persisted var changeType: UpdatableChangeType
    /// Indicates whether the object is deleted locally and needs to be synced with backend
    @Persisted var deleted: Bool

    // MARK: - Sync properties

    var changedFields: RLastReadDateChanges {
        var changes: RLastReadDateChanges = []
        for change in self.changes {
            changes.insert(RLastReadDateChanges(rawValue: change.rawChanges))
        }
        return changes
    }
}
