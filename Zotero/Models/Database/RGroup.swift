//
//  RGroup.swift
//  Zotero
//
//  Created by Michal Rentka on 26/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

enum GroupType: String {
    case `public` = "Public"
    case `private` = "Private"
}

final class RGroup: Object {
    @objc dynamic var identifier: Int = 0
    @objc dynamic var owner: Int = 0
    @objc dynamic var name: String = ""
    @objc dynamic var desc: String = ""
    @objc dynamic var rawType: String = ""
    @objc dynamic var canEditMetadata: Bool = false
    @objc dynamic var canEditFiles: Bool = false
    @objc dynamic var orderId: Int = 0
    @objc dynamic var versions: RVersions?

    // MARK: - Sync data
    /// Flag that indicates that this group is kept only locally on this device, the group was either removed remotely
    // or the user was removed from the group, but the user chose to keep it
    @objc dynamic var isLocalOnly: Bool = false
    /// Indicates local version of object
    @objc dynamic var version: Int = 0
    /// State which indicates whether object is synced with backend data, see ObjectSyncState for more info
    @objc dynamic var rawSyncState: Int = 0

    // MARK: - Object properties

    override class func primaryKey() -> String? {
        return "identifier"
    }

    override class func indexedProperties() -> [String] {
        return ["version"]
    }

    // MARK: - Sync properties

    var syncState: ObjectSyncState {
        get {
            return ObjectSyncState(rawValue: self.rawSyncState) ?? .synced
        }

        set {
            self.rawSyncState = newValue.rawValue
        }
    }

    var type: GroupType {
        get {
            return GroupType(rawValue: self.rawType) ?? .private
        }

        set {
            self.rawType = newValue.rawValue
        }
    }
}
