//
//  Versions.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct Versions: Equatable {
    let collections: Int
    let items: Int
    let trash: Int
    let searches: Int
    let deletions: Int
    let settings: Int

    var max: Int {
        return Swift.max(self.collections,
               Swift.max(self.items,
               Swift.max(self.trash,
               Swift.max(self.searches,
               Swift.max(self.deletions, self.settings)))))
    }

    init(collections: Int, items: Int, trash: Int, searches: Int, deletions: Int, settings: Int) {
        self.collections = collections
        self.items = items
        self.trash = trash
        self.searches = searches
        self.deletions = deletions
        self.settings = settings
    }

    init(versions: RVersions?) {
        self.collections = versions?.collections ?? 0
        self.items = versions?.items ?? 0
        self.trash = versions?.trash ?? 0
        self.searches = versions?.searches ?? 0
        self.deletions = versions?.deletions ?? 0
        self.settings = versions?.settings ?? 0
    }

    static var empty: Versions {
        return Versions(collections: 0, items: 0, trash: 0, searches: 0, deletions: 0, settings: 0)
    }
}
