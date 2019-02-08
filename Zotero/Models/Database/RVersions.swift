//
//  RVersions.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

class RVersions: Object {
    @objc dynamic var collections: Int = 0
    @objc dynamic var items: Int = 0
    @objc dynamic var trash: Int = 0
    @objc dynamic var searches: Int = 0
}
