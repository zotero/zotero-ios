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
    @objc dynamic var key: String = ""
    @objc dynamic var rawType: String = ""
    @objc dynamic var title: String = ""
    @objc dynamic var trash: Bool = false
    @objc dynamic var version: Int = 0
    @objc dynamic var needsSync: Bool = false
    @objc dynamic var parent: RItem?
    @objc dynamic var library: RLibrary?
    let collections: List<RCollection> = List()

    let fields = LinkingObjects(fromType: RItemField.self, property: "item")
    let children = LinkingObjects(fromType: RItem.self, property: "parent")
    let tags = LinkingObjects(fromType: RTag.self, property: "items")

    override class func indexedProperties() -> [String] {
        return ["version", "key"]
    }

    static var titleKeys: [String] = {
        return ["title", "nameOfAct", "caseName", "subject", "note"]
    }()
}

class RItemField: Object {
    @objc dynamic var key: String = ""
    @objc dynamic var value: String = ""
    @objc dynamic var item: RItem?
}
