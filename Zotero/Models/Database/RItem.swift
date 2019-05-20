//
//  RItem.swift
//  Zotero
//
//  Created by Michal Rentka on 07/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct RItemChanges: OptionSet {
    typealias RawValue = Int16

    let rawValue: Int16

    init(rawValue: Int16) {
        self.rawValue = rawValue
    }
}

extension RItemChanges {
    static let type = RItemChanges(rawValue: 1 << 0)
    static let trash = RItemChanges(rawValue: 1 << 1)
    static let parent = RItemChanges(rawValue: 1 << 2)
    static let collections = RItemChanges(rawValue: 1 << 3)
    static let fields = RItemChanges(rawValue: 1 << 4)
    static let tags = RItemChanges(rawValue: 1 << 5)
    static let creators = RItemChanges(rawValue: 1 << 6)
    static let relations = RItemChanges(rawValue: 1 << 7)
    static let all: RItemChanges = [.type, .trash, .parent, .collections, .fields, .tags, .creators, .relations]
}

class RItem: Object {
    @objc dynamic var key: String = ""
    @objc dynamic var rawType: String = ""
    @objc dynamic var title: String = ""
    @objc dynamic var creatorSummary: String = ""
    @objc dynamic var parsedDate: String = ""
    @objc dynamic var trash: Bool = false
    @objc dynamic var version: Int = 0
    /// State which indicates whether object is synced with backend data, see ObjectSyncState for more info
    @objc dynamic var rawSyncState: Int = 0
    /// Raw value for OptionSet of changes for this object, indicates which local changes need to be synced to backend
    @objc dynamic var rawChangedFields: Int16 = 0
    /// Indicates whether the object is deleted locally and needs to be synced with backend
    @objc dynamic var deleted: Bool = false
    @objc dynamic var dateAdded: Date = Date(timeIntervalSince1970: 0)
    @objc dynamic var dateModified: Date = Date(timeIntervalSince1970: 0)
    @objc dynamic var parent: RItem?
    @objc dynamic var customLibrary: RCustomLibrary?
    @objc dynamic var group: RGroup?
    let collections: List<RCollection> = List()

    let fields = LinkingObjects(fromType: RItemField.self, property: "item")
    let children = LinkingObjects(fromType: RItem.self, property: "parent")
    let tags = LinkingObjects(fromType: RTag.self, property: "items")
    let creators = LinkingObjects(fromType: RCreator.self, property: "item")
    let relations = LinkingObjects(fromType: RRelation.self, property: "item")

    var syncState: ObjectSyncState {
        get {
            return ObjectSyncState(rawValue: self.rawSyncState) ?? .synced
        }

        set {
            self.rawSyncState = newValue.rawValue
        }
    }

    var libraryId: LibraryIdentifier? {
        if let custom = self.customLibrary {
            return .custom(custom.type)
        }
        if let group = self.group {
            return .group(group.identifier)
        }
        return nil
    }

    var changedFields: RItemChanges {
        get {
            return RItemChanges(rawValue: self.rawChangedFields)
        }

        set {
            self.rawChangedFields = newValue.rawValue
        }
    }

    override class func indexedProperties() -> [String] {
        return ["version", "key"]
    }
}

class RItemField: Object {
    @objc dynamic var key: String = ""
    @objc dynamic var value: String = ""
    @objc dynamic var item: RItem?
    @objc dynamic var changed: Bool = false
}

class RRelation: Object {
    @objc dynamic var type: String = ""
    @objc dynamic var urlString: String = ""
    @objc dynamic var item: RItem?
}
