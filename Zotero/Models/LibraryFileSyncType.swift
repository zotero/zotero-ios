//
//  LibraryFileSyncType.swift
//  Zotero
//
//  Created by Michal Rentka on 30.01.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

enum LibraryFileSyncType: Int, PersistableEnum {
    case asNeeded
    case atSyncTime
}
