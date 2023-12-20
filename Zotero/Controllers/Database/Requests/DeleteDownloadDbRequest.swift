//
//  DeleteDownloadDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 20.12.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct DeleteDownloadDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        guard let download = database.objects(RDownload.self).filter(.key(key, in: libraryId)).first else { return }
        database.delete(download)
    }
}
