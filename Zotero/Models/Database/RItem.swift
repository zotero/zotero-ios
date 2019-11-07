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
    /// Localized type based on current localization of device, used for sorting
    @objc dynamic var localizedType: String = ""
    @objc dynamic var baseTitle: String = ""
    @objc dynamic var displayTitle: String = ""
    @objc dynamic var sortTitle: String = ""
    /// Summary of creators collected from linked RCreators
    @objc dynamic var creatorSummary: String? = nil
    /// Indicates whether this instance has nonempty creatorSummary, helper variable, used in sorting so that we can show items with summaries
    /// first and sort them in any order we want (asd/desc) and all other items later
    @objc dynamic var hasCreatorSummary: Bool = false
    /// Date that was parsed from "date" field
    @objc dynamic var parsedDate: Date? = nil
    /// Indicates whether this instance has nonempty parsedDate, helper variable, used in sorting so that we can show items with dates
    /// first and sort them in any order we want (asd/desc) and all other items later
    @objc dynamic var hasParsedDate: Bool = false
    /// Year that was parsed from "date" field
    @objc dynamic var parsedYear: String? = nil
    /// Indicates whether this instance has nonempty parsedYear, helper variable, used in sorting so that we can show items with years
    /// first and sort them in any order we want (asd/desc) and all other items later
    @objc dynamic var hasParsedYear: Bool = false
    @objc dynamic var trash: Bool = false
    @objc dynamic var version: Int = 0
    /// Indicates whether attachemnt (file) needs to be uploaded to backend
    @objc dynamic var attachmentNeedsSync: Bool = false
    /// State which indicates whether object is synced with backend data, see ObjectSyncState for more info
    @objc dynamic var rawSyncState: Int = 0
    /// Date when last sync attempt was performed on this object
    @objc dynamic var lastSyncDate: Date = Date(timeIntervalSince1970: 0)
    /// Number of retries for sync of this object
    @objc dynamic var syncRetries: Int = 0
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

    func setTitle(_ title: String) {
        self.baseTitle = title
        self.updateDerivedTitles()
    }

    func updateDerivedTitles() {
        let displayTitle = ItemTitleFormatter.displayTitle(for: self)
        if self.displayTitle != displayTitle {
            self.displayTitle = displayTitle
        }
        self.updateSortTitle()
    }

    private func updateSortTitle() {
        let newTitle = self.displayTitle.trimmingCharacters(in: CharacterSet(charactersIn: "[]'\""))
        if newTitle != self.sortTitle {
            self.sortTitle = newTitle
        }
    }

    func setDateFieldMetadata(_ date: String) {
        let data = self.parseDate(from: date)
        self.parsedYear = data?.0
        self.hasParsedYear = self.parsedYear != nil
        self.parsedDate = data?.1
        self.hasParsedDate = self.parsedDate != nil
    }

    private func parseDate(from dateString: String) -> (String, Date)? {
        guard let date = dateString.parsedDate else { return nil }
        let year = Calendar.current.component(.year, from: date)
        return ("\(year)", date)
    }

    func updateCreators() {
        self.creatorSummary = CreatorSummaryFormatter.summary(for: self.creators.filter("primary = true"))
        self.hasCreatorSummary = self.creatorSummary != nil
    }
}

class RItemField: Object {
    @objc dynamic var key: String = ""
    @objc dynamic var baseKey: String?
    @objc dynamic var value: String = ""
    @objc dynamic var item: RItem?
    @objc dynamic var changed: Bool = false
}

class RRelation: Object {
    @objc dynamic var type: String = ""
    @objc dynamic var urlString: String = ""
    @objc dynamic var item: RItem?
}
