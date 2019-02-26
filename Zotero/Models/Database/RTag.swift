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
    @objc dynamic var color: String = ""
    @objc dynamic var library: RLibrary?
    let items: List<RItem> = List()

    var uiColor: UIColor {
        return UIColor(hex: self.color)
    }

    override class func indexedProperties() -> [String] {
        return ["name"]
    }
}
