//
//  RObjectChange.swift
//  Zotero
//
//  Created by Michal Rentka on 14.09.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

final class RObjectChange: EmbeddedObject {
    @Persisted var uuid: String
    @Persisted var rawChanges: Int16
}
