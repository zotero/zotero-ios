//
//  StoreSettingsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 26/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct StoreSettingsDbRequest: DbRequest {
    let response: SettingsResponse
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        if let response = response.tagColors {
            syncTagColors(tags: response.value, in: database)
        }

        // Additional settings should be returned only by user library, just to be sure, let's ignore group sync
        switch self.libraryId {
        case .group:
            return

        case .custom:
            break
        }

        syncPages(pages: response.pageIndices.indices, in: database)
        syncLastReadValues(values: response.lastReadValues.values, in: database)
    }

    private func syncLastReadValues(values: [LastReadResponse], in database: Realm) {
        for value in values {
            let rDate: RLastReadDate
            if let existing = database.objects(RLastReadDate.self).uniqueObject(key: value.key, libraryId: value.libraryId) {
                rDate = existing
            } else {
                rDate = RLastReadDate()
                database.add(rDate)
                rDate.key = value.key
                rDate.libraryId = value.libraryId
            }
            rDate.date = Date(timeIntervalSince1970: TimeInterval(value.value))
            rDate.version = value.version

            // No CR for settings, if it was changed locally, just reset it
            rDate.deleteAllChanges(database: database)

            // Assign value to item
            if let item = database.objects(RItem.self).uniqueObject(key: value.key, libraryId: value.libraryId) {
                item.lastRead = rDate.date
                item.updateEffectiveLastRead()
            } else {
                let item = RItem()
                item.key = value.key
                item.libraryId = value.libraryId
                item.lastRead = rDate.date
                item.updateEffectiveLastRead()
                item.syncState = .dirty
                item.lastSyncDate = Date(timeIntervalSince1970: 0)
                item.changeType = .sync
                database.add(item)
            }
        }
    }

    private func syncPages(pages: [PageIndexResponse], in database: Realm) {
        for index in pages {
            let rIndex: RPageIndex
            if let existing = database.objects(RPageIndex.self).uniqueObject(key: index.key, libraryId: index.libraryId) {
                rIndex = existing
            } else {
                rIndex = RPageIndex()
                database.add(rIndex)
                rIndex.key = index.key
                rIndex.libraryId = index.libraryId
            }
            rIndex.index = index.value
            rIndex.version = index.version

            // No CR for settings, if it was changed locally, just reset it
            rIndex.deleteAllChanges(database: database)
        }
    }

    private func syncTagColors(tags: [TagColorResponse], in database: Realm) {
        let names = tags.map { $0.name }
        let toDelete = database.objects(RTag.self).filter(.library(with: self.libraryId)).filter("color != \"\" and not name in %@", names)
        for tag in toDelete {
            database.delete(tag.tags)
        }
        database.delete(toDelete)

        let allTags = database.objects(RTag.self)
        for (idx, tag) in tags.enumerated() {
            if let existing = allTags.filter(.name(tag.name, in: self.libraryId)).first {
                var didChange = false
                if existing.color != tag.color {
                    existing.color = tag.color
                    didChange = true
                }
                if existing.order != idx {
                    existing.order = idx
                    didChange = true
                }

                if didChange {
                    for tag in existing.tags {
                        guard let item = tag.item else { continue }
                        // Update item so that items list and tag picker are updated with color/order changes
                        item.rawType = item.rawType
                    }
                }
            } else {
                let new = RTag.create(name: tag.name, color: tag.color, libraryId: libraryId, order: idx)
                database.add(new)
            }
        }
    }
}
