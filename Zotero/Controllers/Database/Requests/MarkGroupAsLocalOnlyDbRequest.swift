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

    var needsWrite: Bool {
        return true
    }

    func process(in database: Realm) throws {
        guard let group = database.object(ofType: RGroup.self, forPrimaryKey: self.groupId) else { return }
        // Mark group as local only and disable editing
        group.isLocalOnly = true
        group.canEditFiles = false
        group.canEditMetadata = false
        // Mark all local changes as synced, we're keeping the group in current state
        let predicate = Predicates.changesInLibrary(libraryId: .group(self.groupId))
        database.objects(RCollection.self).filter(predicate).forEach({ $0.resetChanges() })
        database.objects(RItem.self).filter(predicate).forEach({ $0.resetChanges() })
        database.objects(RSearch.self).filter(predicate).forEach({ $0.resetChanges() })
    }
}
