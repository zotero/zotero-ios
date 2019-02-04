//
//  RUser.swift
//  Zotero
//
//  Created by Michal Rentka on 04/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

class RUser: Object {
    @objc dynamic var identifier: Int64 = 0
    @objc dynamic var name: String = ""

    override class func primaryKey() -> String? {
        return "identifier"
    }
}
