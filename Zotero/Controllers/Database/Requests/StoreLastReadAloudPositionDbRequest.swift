//
//  StoreLastReadAloudPositionDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 24.09.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct StoreLastReadAloudPositionDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier
    let position: ReadAloudResumePosition

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let rPosition: RLastReadAloudPosition

        if let existing = database.objects(RLastReadAloudPosition.self).uniqueObject(key: key, libraryId: libraryId) {
            guard !existing.matches(position: position) else { return }
            rPosition = existing
        } else {
            rPosition = RLastReadAloudPosition()
            database.add(rPosition)
            rPosition.key = key
            rPosition.libraryId = libraryId
        }

        rPosition.position = position
        rPosition.deleted = false
        rPosition.changes.append(RObjectChange.create(changes: RLastReadAloudPositionChanges.position))
        rPosition.changeType = .user
    }
}
