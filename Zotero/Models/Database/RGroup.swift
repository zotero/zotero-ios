//
//  RGroup.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

class RGroup: Object {
    static let myLibraryId: Int = -1

    @objc dynamic var identifier: Int = 0
    @objc dynamic var owner: Int = 0
    @objc dynamic var name: String = ""
    @objc dynamic var desc: String = ""
    @objc dynamic var type: String = ""
    @objc dynamic var libraryReading: String = ""
    @objc dynamic var libraryEditing: String = ""
    @objc dynamic var fileEditing: String = ""
    @objc dynamic var version: Int = 0

    override class func primaryKey() -> String? {
        return "identifier"
    }

    override class func indexedProperties() -> [String] {
        return ["version"]
    }
}
