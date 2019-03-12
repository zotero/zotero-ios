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
    typealias RawValue = UInt

    let rawValue: UInt

    init(rawValue: UInt) {
        self.rawValue = rawValue
    }
}

extension RCollectionChanges {
    static let name = RCollectionChanges(rawValue: 1 << 1)
    static let parent = RCollectionChanges(rawValue: 1 << 2)
    static let all: RCollectionChanges = [.name, .parent]
}

class RCollection: Object {
    @objc dynamic var key: String = ""
    @objc dynamic var name: String = ""
    @objc dynamic var version: Int = 0
    /// Flag that marks whether object has been synced successfully during last sync
    /// False if object was synced, true otherwise
    @objc dynamic var needsSync: Bool = false
    /// Raw value for OptionSet of changes for this object
    @objc dynamic var rawChangedFields: UInt = 0
    @objc dynamic var dateModified: Date = Date(timeIntervalSince1970: 0)
    @objc dynamic var library: RLibrary?
    @objc dynamic var parent: RCollection?

    var changedFields: RCollectionChanges {
        get {
            return RCollectionChanges(rawValue: self.rawChangedFields)
        }

        set {
            self.rawChangedFields = newValue.rawValue
        }
    }

    let items = LinkingObjects(fromType: RItem.self, property: "collections")
    let children = LinkingObjects(fromType: RCollection.self, property: "parent")

    override class func indexedProperties() -> [String] {
        return ["version", "key"]
    }
}
