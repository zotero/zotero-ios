//
//  EndItemDetailEditingDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 12.10.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct EndItemDetailEditingDbRequest: DbRequest {
    var needsWrite: Bool { return true }

    let libraryId: LibraryIdentifier
    let itemKey: String

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(itemKey, in: libraryId)).first else { return }
        item.dateModified = Date()
        item.changesSyncPaused = false
        item.changeType = .user
    }
}
