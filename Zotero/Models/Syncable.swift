//
//  Syncable.swift
//  Zotero
//
//  Created by Michal Rentka on 07/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

typealias Syncable = SyncableObject&Object

protocol SyncableObject: class {
    var key: String { get set }
    var library: RLibrary? { get set }
    var version: Int { get set }
    var needsSync: Bool { get set }

    func removeChildren(in database: Realm)
}
