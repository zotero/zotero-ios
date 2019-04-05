//
//  RGroup.swift
//  Zotero
//
//  Created by Michal Rentka on 26/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

class RGroup: Object {
    @objc dynamic var identifier: Int = 0
    @objc dynamic var owner: Int = 0
    @objc dynamic var name: String = ""
    @objc dynamic var desc: String = ""
    @objc dynamic var type: String = ""
    @objc dynamic var libraryReading: String = ""
    @objc dynamic var libraryEditing: String = ""
    @objc dynamic var fileEditing: String = ""
    @objc dynamic var version: Int = 0
    @objc dynamic var orderId: Int = 0
    @objc dynamic var rawSyncState: Int = 0
    @objc dynamic var versions: RVersions?

    let collections = LinkingObjects(fromType: RCollection.self, property: "group")
    let items = LinkingObjects(fromType: RItem.self, property: "group")
    let searches = LinkingObjects(fromType: RSearch.self, property: "group")
    let tags = LinkingObjects(fromType: RTag.self, property: "group")

    var syncState: ObjectSyncState {
        get {
            return ObjectSyncState(rawValue: self.rawSyncState) ?? .synced
        }

        set {
            self.rawSyncState = newValue.rawValue
        }
    }

    override class func primaryKey() -> String? {
        return "identifier"
    }

    override class func indexedProperties() -> [String] {
        return ["version"]
    }
}
