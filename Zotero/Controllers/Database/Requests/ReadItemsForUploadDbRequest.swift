//
//  ReadItemsForUploadDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 31.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadItemsForUploadDbRequest: DbResponseRequest {
    typealias Response = Results<RItem>

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return false }
    var ignoreNotificationTokens: [NotificationToken]? { return nil }

    func process(in database: Realm) throws -> Results<RItem> {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [.attachmentNeedsUpload, .library(with: self.libraryId)])
        return database.objects(RItem.self).filter(.item(type: ItemTypes.attachment)).filter(predicate)
    }
}
