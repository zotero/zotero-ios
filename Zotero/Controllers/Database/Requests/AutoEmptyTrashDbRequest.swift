//
//  AutoEmptyTrashDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 15.10.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import CocoaLumberjackSwift
import RealmSwift

struct AutoEmptyTrashDbRequest: DbRequest {
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let threshold = Defaults.shared.trashAutoEmptyThreshold
        var count = 0
        database.objects(RItem.self).filter(.items(for: .custom(.trash), libraryId: libraryId)).filter("trashDate != nil").forEach {
            guard let date = $0.trashDate, shouldDelete(date: date) else { return }
            $0.deleted = true
            $0.changeType = .user
            count += 1
        }
        DDLogInfo("Auto emptied \(count) items")
        count = 0
        database.objects(RCollection.self).filter(.trashedCollections(in: .custom(.myLibrary))).filter("trashDate != nil").forEach {
            guard let date = $0.trashDate, shouldDelete(date: date) else { return }
            $0.deleted = true
            $0.changeType = .user
            count += 1
        }
        DDLogInfo("Auto emptied \(count) collections")

        func shouldDelete(date: Date) -> Bool {
            let daysSinceTrashed = Int(Date.now.timeIntervalSince(date) / 86400)
            return daysSinceTrashed >= threshold
        }
    }
}
