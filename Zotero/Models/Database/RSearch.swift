//
//  RSearch.swift
//  Zotero
//
//  Created by Michal Rentka on 25/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

class RSearch: Object {
    @objc dynamic var key: String = ""
    @objc dynamic var name: String = ""
    @objc dynamic var version: Int = 0
    @objc dynamic var needsSync: Bool = false
    @objc dynamic var library: RLibrary?
    let conditions = LinkingObjects(fromType: RCondition.self, property: "searches")
}

class RCondition: Object {
    @objc dynamic var condition: String = ""
    @objc dynamic var `operator`: String = ""
    @objc dynamic var value: String = ""
    let searches: List<RSearch> = List()
}
