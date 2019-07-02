//
//  MarkAllLibraryObjectsAsSyncedDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 02/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MarkAllLibraryObjectsAsSyncedDbRequest: DbRequest {
    let library: SyncController.Library

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let predicate = Predicates.changesInLibrary(libraryId: self.library.libraryId)
        database.objects(RCollection.self).filter(predicate).forEach({ $0.resetChanges() })
        database.objects(RItem.self).filter(predicate).forEach({ $0.resetChanges() })
        database.objects(RSearch.self).filter(predicate).forEach({ $0.resetChanges() })
    }
}
