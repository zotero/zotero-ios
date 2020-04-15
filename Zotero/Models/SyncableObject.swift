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

/// State which indicates whether local object is synced with backend data.
/// .synced - object is up to date
/// .dirty - object has not yet been synced, it is just a placeholder that shouldn't be visible to the user
/// .outdated - object has been synced before, but most recent sync failed and it needs to resync
enum ObjectSyncState: Int {
    case synced, dirty, outdated
}

protocol Syncable: class {
    var key: String { get set }
    var customLibrary: RCustomLibrary? { get set }
    var group: RGroup? { get set }
    var version: Int { get set }
    var rawSyncState: Int { get set }
    var lastSyncDate: Date { get set }
    var syncRetries: Int { get set }
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

    var syncState: ObjectSyncState {
        get {
            return ObjectSyncState(rawValue: self.rawSyncState) ?? .synced
        }

        set {
            self.rawSyncState = newValue.rawValue
        }
    }
}

extension RCollection: Syncable {}
extension RItem: Syncable {}
extension RSearch: Syncable {}
