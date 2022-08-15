//
//  ReadAllDownloadedAndForUploadItemsDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 25.05.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadAllDownloadedAndForUploadItemsDbRequest: DbResponseRequest {
    typealias Response = Results<RItem>

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> Results<RItem> {
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [.file(downloaded: true), .attachmentNeedsUpload])
        return database.objects(RItem.self).filter(.item(type: ItemTypes.attachment)).filter(predicate)
    }
}
