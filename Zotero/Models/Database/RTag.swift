//
//  RTag.swift
//  Zotero
//
//  Created by Michal Rentka on 25/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

class RTag: Object {
    @objc dynamic var name: String = ""
    let items: List<RItem> = List()

    override class func primaryKey() -> String? {
        return "name"
    }
}
