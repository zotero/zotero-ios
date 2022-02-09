//
//  RCollection.swift
//  Zotero
//
//  Created by Michal Rentka on 07/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct RCollectionChanges: OptionSet {
    typealias RawValue = Int16

    let rawValue: Int16

    init(rawValue: Int16) {
        self.rawValue = rawValue
    }
}

extension RCollectionChanges {
    static let name = RCollectionChanges(rawValue: 1 << 0)
    static let parent = RCollectionChanges(rawValue: 1 << 1)
    static let all: RCollectionChanges = [.name, .parent]
}

final class RCollection: Object {
    static let observableKeypathsForList: [String] = ["name", "parentKey", "items"]

    @Persisted(indexed: true) var key: String
    @Persisted var name: String
    @Persisted var dateModified: Date
    @Persisted var parentKey: String?
    @Persisted var collapsed: Bool = true
    @Persisted var lastUsed: Date

    @Persisted var items: List<RItem>
    @Persisted var customLibraryKey: RCustomLibraryType?
    @Persisted var groupKey: Int?

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

    var changedFields: RCollectionChanges {
        get {
            return RCollectionChanges(rawValue: self.rawChangedFields)
        }

        set {
            self.rawChangedFields = newValue.rawValue
        }
    }
}
