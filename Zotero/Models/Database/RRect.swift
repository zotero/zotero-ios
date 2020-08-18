//
//  RRect.swift
//  Zotero
//
//  Created by Michal Rentka on 18/08/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

class RRect: Object {
    @objc dynamic var x: Double = 0
    @objc dynamic var y: Double = 0
    @objc dynamic var width: Double = 0
    @objc dynamic var height: Double = 0
}
