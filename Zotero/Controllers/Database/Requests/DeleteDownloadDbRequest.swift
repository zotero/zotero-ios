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

struct DeleteDownloadsDbRequest: DbResponseRequest {
    typealias Response = Set<AttachmentDownloader.Download>

    let keys: Set<String>
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> Set<AttachmentDownloader.Download> {
        var result: Set<AttachmentDownloader.Download> = []
        let downloads = database.objects(RDownload.self).filter(.keys(keys, in: libraryId))
        for download in downloads {
            guard let libraryId = download.libraryId else { continue }
            result.insert(AttachmentDownloader.Download(key: download.key, parentKey: download.parentKey, libraryId: libraryId))
        }
        database.delete(downloads)
        return result
    }
}

struct DeleteLibraryDownloadsDbRequest: DbResponseRequest {
    typealias Response = Set<AttachmentDownloader.Download>

    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws -> Set<AttachmentDownloader.Download> {
        var result: Set<AttachmentDownloader.Download> = []
        let downloads = database.objects(RDownload.self).filter(.library(with: libraryId))
        for download in downloads {
            guard let libraryId = download.libraryId else { continue }
            result.insert(AttachmentDownloader.Download(key: download.key, parentKey: download.parentKey, libraryId: libraryId))
        }
        database.delete(downloads)
        return result
    }
}

struct DeleteAllDownloadsDbRequest: DbRequest {
    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        database.delete(database.objects(RDownload.self))
    }
}
