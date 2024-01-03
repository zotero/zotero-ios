//
//  MarkFileAsDownloadedDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 15.04.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift
import RealmSwift

struct MarkFileAsDownloadedDbRequest: DbRequest {
    let key: String
    let libraryId: LibraryIdentifier
    let downloaded: Bool
    let compressed: Bool?

    var needsWrite: Bool { return true }

    init(key: String, libraryId: LibraryIdentifier, downloaded: Bool, compressed: Bool? = nil) {
        self.key = key
        self.libraryId = libraryId
        self.downloaded = downloaded
        self.compressed = compressed
    }

    func process(in database: Realm) throws {
        guard let item = database.objects(RItem.self).filter(.key(key, in: libraryId)).first else {
            DDLogError("MarkFileAsDownloadedDbRequest: item not found")
            return
        }
        guard item.rawType == ItemTypes.attachment else { return }
        if item.fileDownloaded != downloaded {
            item.fileDownloaded = downloaded
        }
        if let compressed, item.fileCompressed != compressed {
            item.fileCompressed = compressed
        }
    }
}

struct MarkItemsFilesAsNotDownloadedDbRequest: DbRequest {
    let keys: Set<String>
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let items = database.objects(RItem.self).filter(.keys(keys, in: libraryId)).filter(.item(type: ItemTypes.attachment)).filter(.file(downloaded: true))
        for item in items {
            guard !item.attachmentNeedsSync else { continue }
            item.fileDownloaded = false
        }
    }
}

struct MarkLibraryFilesAsNotDownloadedDbRequest: DbRequest {
    let libraryId: LibraryIdentifier

    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let items = database.objects(RItem.self).filter(.library(with: libraryId)).filter(.item(type: ItemTypes.attachment)).filter(.file(downloaded: true))
        for item in items {
            guard !item.attachmentNeedsSync else { continue }
            item.fileDownloaded = false
        }
    }
}

struct MarkAllFilesAsNotDownloadedDbRequest: DbRequest {
    var needsWrite: Bool { return true }

    func process(in database: Realm) throws {
        let items = database.objects(RItem.self).filter(.item(type: ItemTypes.attachment)).filter(.file(downloaded: true))
        for item in items {
            guard !item.attachmentNeedsSync else { continue }
            item.fileDownloaded = false
        }
    }
}
