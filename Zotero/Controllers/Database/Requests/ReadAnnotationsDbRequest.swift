//
//  ReadAnnotationsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 18/08/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadAnnotationsDbRequest: DbResponseRequest {
    typealias Response = Results<RItem>

    let attachmentKey: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RItem> {
        return database.objects(RItem.self).filter(.parentKey(self.attachmentKey, in: self.libraryId))
                                           .filter(.items(type: ItemTypes.annotation, notSyncState: .dirty))
                                           .filter(.deleted(false))
                                           .sorted(byKeyPath: "annotationSortIndex")
    }
}
