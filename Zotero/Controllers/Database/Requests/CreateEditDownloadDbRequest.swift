//
//  CreateEditDownloadDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 20.12.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct CreateEditDownloadDbRequest: DbRequest {
    let taskId: Int
    let key: String
    let parentKey: String?
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        if let download = database.objects(RDownload.self).filter(.key(key, in: libraryId)).first {
            if download.taskId != taskId {
                download.taskId = taskId
            }
            if download.parentKey != parentKey {
                download.parentKey = parentKey
            }
            return
        }

        let download = RDownload()
        download.taskId = taskId
        download.key = key
        download.parentKey = parentKey
        download.libraryId = libraryId
        database.add(download)
    }
}
