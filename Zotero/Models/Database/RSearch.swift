//
//  RSearch.swift
//  Zotero
//
//  Created by Michal Rentka on 25/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct RSearchChanges: OptionSet {
    typealias RawValue = Int16

    let rawValue: Int16

    init(rawValue: Int16) {
        self.rawValue = rawValue
    }
}

extension RSearchChanges {
    static let name = RSearchChanges(rawValue: 1 << 0)
    static let conditions = RSearchChanges(rawValue: 1 << 1)
    static let all: RSearchChanges = [.name, .conditions]
}

final class RSearch: Object {
    @Persisted(indexed: true) var key: String
    @Persisted var name: String
    @Persisted var dateModified: Date
    @Persisted var customLibraryKey: RCustomLibraryType?
    @Persisted var groupKey: Int?
    @Persisted var conditions: List<RCondition>

    // MARK: - Sync data
    /// Indicates local version of object
    @Persisted(indexed: true) var version: Int
    /// State which indicates whether object is synced with backend data, see ObjectSyncState for more info
    @Persisted var syncState: ObjectSyncState
    /// Date when last sync attempt was performed on this object
    @Persisted var lastSyncDate: Date
    /// Number of retries for sync of this object
    @Persisted var syncRetries: Int
    /// Raw value for OptionSet of changes for this object, indicates which local changes need to be synced to backend
    @Persisted var rawChangedFields: Int16
    /// Raw value for `UpdatableChangeType`, indicates whether current update of item has been made by user or sync process.
    @Persisted var changeType: UpdatableChangeType
    /// Indicates whether the object is deleted locally and needs to be synced with backend
    @Persisted var deleted: Bool
    /// Indicates whether the object is trashed locally and needs to be synced with backend
    @Persisted var trash: Bool

    // MARK: - Sync properties

    var changedFields: RSearchChanges {
        get {
            return RSearchChanges(rawValue: self.rawChangedFields)
        }

        set {
            self.rawChangedFields = newValue.rawValue
        }
    }
}

final class RCondition: EmbeddedObject {
    @Persisted var condition: String
    @Persisted var `operator`: String
    @Persisted var value: String
    @Persisted var sortId: Int
}
