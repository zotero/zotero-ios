//
//  RCollection.swift
//  Zotero
//
//  Created by Michal Rentka on 07/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

class RCollection: Object {
    @objc dynamic var key: String = ""
    @objc dynamic var name: String = ""
    @objc dynamic var version: Int = 0
    /// Flag that marks whether object has been synced successfully during last sync
    /// False if object was synced, true otherwise
    @objc dynamic var needsSync: Bool = false
    /// Comma separated names of variables which were changed since last sync
    @objc dynamic var changedFields: String = ""
    @objc dynamic var dateModified: Date = Date(timeIntervalSince1970: 0)
    @objc dynamic var library: RLibrary?
    @objc dynamic var parent: RCollection?

    let items = LinkingObjects(fromType: RItem.self, property: "collections")
    let children = LinkingObjects(fromType: RCollection.self, property: "parent")

    override class func indexedProperties() -> [String] {
        return ["version", "key"]
    }
}
