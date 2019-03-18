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
    /// Flag that marks whether object has been synced successfully during last sync
    /// False if object was synced, true otherwise
    @objc dynamic var needsSync: Bool = false
    /// Raw value for OptionSet of changes for this object
    @objc dynamic var rawChangedFields: Int16 = 0
    @objc dynamic var dateAdded: Date = Date(timeIntervalSince1970: 0)
    @objc dynamic var dateModified: Date = Date(timeIntervalSince1970: 0)
    @objc dynamic var parent: RItem?
    @objc dynamic var library: RLibrary?
    let collections: List<RCollection> = List()

    let fields = LinkingObjects(fromType: RItemField.self, property: "item")
    let children = LinkingObjects(fromType: RItem.self, property: "parent")
    let tags = LinkingObjects(fromType: RTag.self, property: "items")
    let creators = LinkingObjects(fromType: RCreator.self, property: "items")
    let relations = LinkingObjects(fromType: RRelation.self, property: "item")

    var type: ItemType {
        return ItemType(rawValue: self.rawType) ?? .unknown
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

    static var titleKeys: [String] = {
        return ["title", "nameOfAct", "caseName", "subject", "note"]
    }()
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
