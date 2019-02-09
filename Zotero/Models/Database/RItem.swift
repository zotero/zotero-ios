//
//  RItem.swift
//  Zotero
//
//  Created by Michal Rentka on 07/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

class RItem: Object {
    @objc dynamic var identifier: String = ""
    @objc dynamic var title: String = ""
    @objc dynamic var trash: Bool = false
    @objc dynamic var version: Int = 0
    @objc dynamic var needsSync: Bool = false
    @objc dynamic var parent: RItem?
    @objc dynamic var library: RLibrary?
    let collections: List<RCollection> = List()

    let children = LinkingObjects(fromType: RItem.self, property: "parent")

    override class func primaryKey() -> String? {
        return "identifier"
    }

    override class func indexedProperties() -> [String] {
        return ["version"]
    }
}
