//
//  RRect.swift
//  Zotero
//
//  Created by Michal Rentka on 18/08/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

final class RRect: Object {
    @objc dynamic var minX: Double = 0
    @objc dynamic var minY: Double = 0
    @objc dynamic var maxX: Double = 0
    @objc dynamic var maxY: Double = 0
}
