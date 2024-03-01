//
//  ReadAttachmentItemsNotInSetDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 01.02.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadAttachmentItemsNotInArrayDbRequest: DbResponseRequest {
    typealias Response = Results<RItem>

    let keys: [String]
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RItem> {
        return database.objects(RItem.self).filter(.allAttachments(for: .custom(.all), libraryId: libraryId)).filter(.key(notIn: keys))
    }
}
