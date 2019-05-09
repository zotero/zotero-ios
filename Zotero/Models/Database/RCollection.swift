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

class RCollection: Object {
    @objc dynamic var key: String = ""
    @objc dynamic var name: String = ""
    @objc dynamic var version: Int = 0
    /// State which indicates whether object is synced with backend data, see ObjectSyncState for more info
    @objc dynamic var rawSyncState: Int = 0
    /// Raw value for OptionSet of changes for this object, indicates which local changes need to be synced to backend
    @objc dynamic var rawChangedFields: Int16 = 0
    /// Indicates whether the object is deleted locally and needs to be synced with backend
    @objc dynamic var deleted: Bool = false
    @objc dynamic var dateModified: Date = Date(timeIntervalSince1970: 0)
    @objc dynamic var customLibrary: RCustomLibrary?
    @objc dynamic var group: RGroup?
    @objc dynamic var parent: RCollection?

    let items = LinkingObjects(fromType: RItem.self, property: "collections")
    let children = LinkingObjects(fromType: RCollection.self, property: "parent")

    var changedFields: RCollectionChanges {
        get {
            return RCollectionChanges(rawValue: self.rawChangedFields)
        }

        set {
            self.rawChangedFields = newValue.rawValue
        }
    }

    var syncState: ObjectSyncState {
        get {
            return ObjectSyncState(rawValue: self.rawSyncState) ?? .synced
        }

        set {
            self.rawSyncState = newValue.rawValue
        }
    }

    override class func indexedProperties() -> [String] {
        return ["version", "key"]
    }
}
