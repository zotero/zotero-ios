//
//  RRelation.swift
//  Zotero
//
//  Created by Michal Rentka on 09/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

class RRelation: Object {
    @objc dynamic var type: String = ""
    @objc dynamic var urlString: String = ""
    @objc dynamic var item: RItem?
}
