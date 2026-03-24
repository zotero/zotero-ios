//
//  StoreLastReadDateDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 20.03.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct StoreLastReadDatesDbRequest: DbRequest {
    struct Data {
        let key: String
        let libraryId: LibraryIdentifier
        let date: Date?
    }

    let array: [Data]

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        try array.forEach({ try StoreLastReadDateDbRequest(key: $0.key, libraryId: $0.libraryId, date: $0.date).process(in: database) })
    }
}

struct StoreLastReadDateDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier
    let date: Date?

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).uniqueObject(key: key, libraryId: libraryId), item.lastRead != date else { return }
        item.lastRead = date

        switch libraryId {
        case .custom(let type):
            switch type {
            case .myLibrary:
                handleMyLibraryDate()
            }

        case .group:
            handleGroupDate()
        }

        func handleMyLibraryDate() {
            item.changes.append(RObjectChange.create(changes: RItemChanges.lastRead))
            item.changeType = .user
        }

        func handleGroupDate() {
            let lastReadDate: RLastReadDate
            if let existing = database.objects(RLastReadDate.self).uniqueObject(key: key, libraryId: libraryId) {
                guard existing.date != date else { return }
                lastReadDate = existing
            } else {
                lastReadDate = RLastReadDate()
                database.add(lastReadDate)
                lastReadDate.key = key
                lastReadDate.libraryId = libraryId
            }

            if let date {
                lastReadDate.date = date
                lastReadDate.changes.append(RObjectChange.create(changes: RLastReadDateChanges.date))
            } else {
                lastReadDate.deleted = true
            }
            lastReadDate.changeType = .user
        }
    }
}
