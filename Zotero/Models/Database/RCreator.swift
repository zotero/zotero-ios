//
//  RCreator.swift
//  Zotero
//
//  Created by Michal Rentka on 25/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

class RCreator: Object {
    @objc dynamic var rawType: String = ""
    @objc dynamic var firstName: String = ""
    @objc dynamic var lastName: String = ""
    let items: List<RItem> = List()
}
