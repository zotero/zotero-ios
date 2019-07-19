//
//  MarkAttachmentUploadedDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 19/07/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct MarkAttachmentUploadedDbRequest: DbRequest {
    let libraryId: LibraryIdentifier
    let key: String

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let attachment = database.objects(RItem.self).filter(Predicates.key(self.key, in: self.libraryId)).first else { return }
    }
}
