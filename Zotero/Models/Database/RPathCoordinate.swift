//
//  RPath.swift
//  Zotero
//
//  Created by Michal Rentka on 30.08.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

final class RPath: EmbeddedObject {
    @Persisted var sortIndex: Int
    @Persisted var coordinates: List<RPathCoordinate>
}

final class RPathCoordinate: EmbeddedObject {
    @Persisted var value: Double
    @Persisted var sortIndex: Int
}
