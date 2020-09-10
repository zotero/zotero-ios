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
    @objc dynamic var baseTitle: String = ""
    @objc dynamic var dateAdded: Date = Date(timeIntervalSince1970: 0)
    @objc dynamic var dateModified: Date = Date(timeIntervalSince1970: 0)
    @objc dynamic var parent: RItem?
    @objc dynamic var customLibrary: RCustomLibrary?
    @objc dynamic var group: RGroup?
    @objc dynamic var mainAttachment: RItem?
    @objc dynamic var createdBy: RUser?
    @objc dynamic var lastModifiedBy: RUser?
    let collections: List<RCollection> = List()

    let fields = LinkingObjects(fromType: RItemField.self, property: "item")
    let children = LinkingObjects(fromType: RItem.self, property: "parent")
    let tags = LinkingObjects(fromType: RTag.self, property: "items")
    let creators = LinkingObjects(fromType: RCreator.self, property: "item")
    let links = LinkingObjects(fromType: RLink.self, property: "item")
    let relations = LinkingObjects(fromType: RRelation.self, property: "item")
    let annotations = LinkingObjects(fromType: RAnnotation.self, property: "item")

    // MARK: - Derived data
    /// Localized type based on current localization of device, used for sorting
    @objc dynamic var localizedType: String = ""
    /// Title which is displayed in items list
    @objc dynamic var displayTitle: String = ""
    /// Title by which the item list is sorted
    @objc dynamic var sortTitle: String = ""
    /// Summary of creators collected from linked RCreators
    @objc dynamic var creatorSummary: String? = nil
    /// Summary of creators used for sorting
    @objc dynamic var sortCreatorSummary: String? = nil
    /// Indicates whether this instance has nonempty creatorSummary, helper variable, used in sorting so that we can show items with summaries
    /// first and sort them in any order we want (asd/desc) and all other items later
    @objc dynamic var hasCreatorSummary: Bool = false
    /// Date that was parsed from "date" field
    @objc dynamic var parsedDate: Date? = nil
    /// Indicates whether this instance has nonempty parsedDate, helper variable, used in sorting so that we can show items with dates
    /// first and sort them in any order we want (asd/desc) and all other items later
    @objc dynamic var hasParsedDate: Bool = false
    /// Year that was parsed from "date" field
    @objc dynamic var parsedYear: Int = 0
    /// Indicates whether this instance has nonempty parsedYear, helper variable, used in sorting so that we can show items with years
    /// first and sort them in any order we want (asd/desc) and all other items later
    @objc dynamic var hasParsedYear: Bool = false
    /// Value taken from publisher field
    @objc dynamic var publisher: String? = nil
    /// Indicates whether this instance has nonempty publisher, helper variable, used in sorting so that we can show items with publishers
    /// first and sort them in any order we want (asd/desc) and all other items later
    @objc dynamic var hasPublisher: Bool = false
    /// Value taken from publicationTitle field
    @objc dynamic var publicationTitle: String? = nil
    /// Indicates whether this instance has nonempty publicationTitle, helper variable, used in sorting so that we can show items with titles
    /// first and sort them in any order we want (asd/desc) and all other items later
    @objc dynamic var hasPublicationTitle: Bool = false

    // MARK: - Sync data
    /// Indicates whether the object is trashed locally and needs to be synced with backend
    @objc dynamic var trash: Bool = false
    /// Indicates local version of object
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
    /// Raw value for `UpdatableChangeType`, indicates whether current update of item has been made by user or sync process.
    @objc dynamic var rawChangeType: Int = 0
    /// Indicates whether the object is deleted locally and needs to be synced with backend
    @objc dynamic var deleted: Bool = false

    var attachment: RItem? {
        if self.rawType == ItemTypes.attachment {
            return self
        }
        return self.mainAttachment
    }

    // MARK: - Object properties

    override class func indexedProperties() -> [String] {
        return ["version", "key"]
    }

    // MARK: - Sync properties

    var changedFields: RItemChanges {
        get {
            return RItemChanges(rawValue: self.rawChangedFields)
        }

        set {
            self.rawChangedFields = newValue.rawValue
        }
    }

    // MARK: - Helpers

    func set(title: String) {
        self.baseTitle = title
        self.updateDerivedTitles()
    }

    func set(publicationTitle: String?) {
        self.publicationTitle = publicationTitle?.lowercased()
        self.hasPublicationTitle = publicationTitle?.isEmpty == false
    }

    func set(publisher: String?) {
        self.publisher = publisher?.lowercased()
        self.hasPublisher = publisher?.isEmpty == false
    }

    func updateDerivedTitles() {
        let displayTitle = ItemTitleFormatter.displayTitle(for: self)
        if self.displayTitle != displayTitle {
            self.displayTitle = displayTitle
        }
        self.updateSortTitle()
    }

    private func updateSortTitle() {
        let newTitle = self.displayTitle.trimmingCharacters(in: CharacterSet(charactersIn: "[]'\"")).lowercased()
        if newTitle != self.sortTitle {
            self.sortTitle = newTitle
        }
    }

    func setDateFieldMetadata(_ date: String?, parser: DateParser) {
        let components = date.flatMap({ parser.parse(string: $0) })
        self.parsedYear = components?.year ?? 0
        self.hasParsedYear = self.parsedYear != 0
        self.parsedDate = components?.date
        self.hasParsedDate = self.parsedDate != nil
    }

    func updateCreatorSummary() {
        self.creatorSummary = CreatorSummaryFormatter.summary(for: self.creators.filter("primary = true"))
        self.sortCreatorSummary = self.creatorSummary?.lowercased()
        self.hasCreatorSummary = self.creatorSummary != nil
    }

    /// Chooses main attachment in the following order:
    /// - oldest PDF attachment matching parent URL,
    /// - oldest PDF attachment not matching parent URL,
    /// - oldest non-PDF attachment matching parent URL,
    /// - oldest non-PDF attachment not matching parent URL.
    func updateMainAttachment() {
        guard self.parent == nil else {
            self.mainAttachment = nil
            return
        }

        let attachments = self.children.filter(.items(type: ItemTypes.attachment, notSyncState: .dirty, trash: false))
                                       .sorted(byKeyPath: "dateAdded", ascending: true)
                                       .filter({ attachment in
                                           let linkMode = attachment.fields.filter(.key(ItemFieldKeys.linkMode)).first?.value
                                           return linkMode == "imported_file" || linkMode == "imported_url"
                                       })

        guard attachments.count > 0 else {
            self.mainAttachment = nil
            return
        }

        let url = self.fields.filter(.key(ItemFieldKeys.url)).first?.value
        let pdfs = attachments.filter({ $0.fields.filter(.key(ItemFieldKeys.contentType)).first?.value == "application/pdf" })

        if pdfs.count > 0 {
            if let url = url, let matchingUrl = pdfs.first(where: { $0.fields.filter(.key(ItemFieldKeys.url)).first?.value == url }) {
                self.mainAttachment = matchingUrl
                return
            }

            self.mainAttachment = pdfs.first
            return
        }

        if let url = url, let matchingUrl = attachments.first(where: { $0.fields.filter(.key(ItemFieldKeys.url)).first?.value == url }) {
            self.mainAttachment = matchingUrl
            return
        }

        self.mainAttachment = attachments.first
    }
}

class RItemField: Object {
    @objc dynamic var key: String = ""
    @objc dynamic var baseKey: String?
    @objc dynamic var value: String = ""
    @objc dynamic var item: RItem?
    @objc dynamic var changed: Bool = false
}
