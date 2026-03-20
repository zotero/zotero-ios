//
//  StoreSettingsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 26/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

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
        let groupedByLibrary = Dictionary(grouping: values, by: \.libraryId)
        for (libraryId, responses) in groupedByLibrary {
            let keys = responses.map(\.key)
            let valuesByKey = Dictionary(responses.map({ ($0.key, $0.value) }), uniquingKeysWith: { $1 })

            let matchingItems = database.objects(RItem.self).filter(.keys(keys, in: libraryId))
            for item in matchingItems {
                item.lastRead = Date(timeIntervalSince1970: Double(valuesByKey[item.key] ?? 0))
            }

            let otherItems = database.objects(RItem.self).filter(.key(notIn: keys, in: libraryId))
            for item in otherItems {
                item.lastRead = nil
            }
        }
    }

    private func syncPages(pages: [PageIndexResponse], in database: Realm) {
        let indices = database.objects(RPageIndex.self).filter(.library(with: self.libraryId))
        for index in pages {
            let rIndex: RPageIndex
            if let existing = indices.filter(.key(index.key)).first {
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
