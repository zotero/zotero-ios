//
//  MarkGroupAsLocalOnlyDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 02/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MarkGroupAsLocalOnlyDbRequest: DbRequest {
    let groupId: Int

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let group = database.object(ofType: RGroup.self, forPrimaryKey: self.groupId) else { return }
        // Mark group as local only and disable editing
        group.isLocalOnly = true
        group.canEditFiles = false
        group.canEditMetadata = false

        // Since the group will be local only, we want to keep the current state of the group as synced
        try MarkAllLibraryObjectChangesAsSyncedDbRequest(libraryId: .group(self.groupId)).process(in: database)
    }
}
