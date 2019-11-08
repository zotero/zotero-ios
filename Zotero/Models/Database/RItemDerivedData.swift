//
//  RItemDerivedData.swift
//  Zotero
//
//  Created by Michal Rentka on 08/11/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

class RItemDerivedData: Object {
    /// Localized type based on current localization of device, used for sorting
    @objc dynamic var localizedType: String = ""
    /// Title that will be displayed in item list
    @objc dynamic var displayTitle: String = ""
    /// Title that is used for sorting in item list
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

    let items = LinkingObjects(fromType: RItem.self, property: "derivedData")

    func updateDerivedTitles() {
        guard let item = self.items.first else { return }
        let displayTitle = ItemTitleFormatter.displayTitle(for: item)
        if self.displayTitle != displayTitle {
            self.displayTitle = displayTitle
        }
        self.updateSortTitle()
    }

    func updateSortTitle() {
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
        guard let creators = self.items.first?.creators else { return }
        self.creatorSummary = CreatorSummaryFormatter.summary(for: creators.filter("primary = true"))
        self.hasCreatorSummary = self.creatorSummary != nil
    }
}
