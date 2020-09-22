//
//  RUser.swift
//  Zotero
//
//  Created by Michal Rentka on 22/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

class RUser: Object {
    @objc dynamic var identifier: Int = 0
    @objc dynamic var name: String = ""
    @objc dynamic var username: String = ""

    let createdBy = LinkingObjects(fromType: RItem.self, property: "createdBy")
    let modifiedBy = LinkingObjects(fromType: RItem.self, property: "lastModifiedBy")

    override class func primaryKey() -> String? {
        return "identifier"
    }
}
