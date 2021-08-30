//
//  RPath.swift
//  Zotero
//
//  Created by Michal Rentka on 30.08.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

final class RPath: Object {
    @objc dynamic var sortIndex: Int = 0
    let coordinates: List<RPathCoordinate> = List()
}

final class RPathCoordinate: Object {
    @objc dynamic var value: Double = 0
    @objc dynamic var sortIndex: Int = 0
}
