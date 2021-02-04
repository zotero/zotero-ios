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
    @objc dynamic var key: String = ""
    @objc dynamic var name: String = ""
    @objc dynamic var dateModified: Date = Date(timeIntervalSince1970: 0)
    @objc dynamic var parent: RCollection?

    let items: List<RItem> = List()
    let customLibraryKey = RealmOptional<Int>()
    let groupKey = RealmOptional<Int>()
    let children = LinkingObjects(fromType: RCollection.self, property: "parent")

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
    /// Indicates whether the object is deleted locally and needs to be synced with backend
    @objc dynamic var deleted: Bool = false
    /// Indicates whether the object is trashed locally and needs to be synced with backend
    @objc dynamic var trash: Bool = false

    // MARK: - Object properties

    override class func indexedProperties() -> [String] {
        return ["version", "key"]
    }

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
