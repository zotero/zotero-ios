//
//  RRect.swift
//  Zotero
//
//  Created by Michal Rentka on 18/08/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

final class RRect: EmbeddedObject {
    @Persisted var minX: Double
    @Persisted var minY: Double
    @Persisted var maxX: Double
    @Persisted var maxY: Double
}
