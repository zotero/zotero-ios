//
//  EditLibrarySyncTypeDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 30.01.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct EditLibrarySyncTypeDbRequest: DbRequest {
    let identifier: LibraryIdentifier
    let syncType: LibraryFileSyncType

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        switch identifier {
        case .custom(let type):
            guard let library = database.object(ofType: RCustomLibrary.self, forPrimaryKey: type.rawValue) else { return }
            library.fileSyncType = syncType

        case .group(let groupId):
            guard let group = database.object(ofType: RGroup.self, forPrimaryKey: groupId) else { return }
            group.fileSyncType = syncType
        }
    }
}
