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

protocol Syncable: AnyObject {
    var key: String { get set }
    var customLibraryKey: RealmOptional<Int> { get }
    var groupKey: RealmOptional<Int> { get }
    var version: Int { get set }
    var rawSyncState: Int { get set }
    var lastSyncDate: Date { get set }
    var syncRetries: Int { get set }
    var isInvalidated: Bool { get }
}

extension Syncable {
    var libraryId: LibraryIdentifier? {
        get {
            guard !self.isInvalidated else { return nil }
            
            if let key = self.customLibraryKey.value, let type = RCustomLibraryType(rawValue: key) {
                return .custom(type)
            }
            if let key = self.groupKey.value {
                return .group(key)
            }
            return nil
        }

        set {
            guard let identifier = newValue else {
                self.groupKey.value = nil
                self.customLibraryKey.value = nil
                return
            }

            switch identifier {
            case .custom(let type):
                self.customLibraryKey.value = type.rawValue
            case .group(let id):
                self.groupKey.value = id
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
extension RPageIndex: Syncable {}
