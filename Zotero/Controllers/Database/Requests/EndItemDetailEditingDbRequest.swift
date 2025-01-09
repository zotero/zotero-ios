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
        guard let item = database.objects(RItem.self).uniqueObject(key: itemKey, libraryId: libraryId) else { return }
        item.changesSyncPaused = false
        item.changeType = .user
    }
}
