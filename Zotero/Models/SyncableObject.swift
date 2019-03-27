//
//  Syncable.swift
//  Zotero
//
//  Created by Michal Rentka on 07/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

typealias SyncableObject = Syncable&Object

protocol Syncable: class {
    var key: String { get set }
    var customLibrary: RCustomLibrary? { get set }
    var group: RGroup? { get set }
    var version: Int { get set }
    var needsSync: Bool { get set }

    func removeChildren(in database: Realm)
}

extension Syncable {
    var libraryObject: LibraryObject? {
        get {
            if let object = self.customLibrary {
                return .custom(object)
            }
            if let object = self.group {
                return .group(object)
            }
            return nil
        }

        set {
            guard let object = newValue else {
                self.group = nil
                self.customLibrary = nil
                return
            }

            switch object {
            case .custom(let object):
                self.customLibrary = object
            case .group(let object):
                self.group = object
            }
        }
    }
}
