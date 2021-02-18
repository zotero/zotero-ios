//
//  LibraryData.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

struct LibraryData {
    let identifier: LibraryIdentifier
    let name: String
    let versions: Versions
    let canEditMetadata: Bool
    let canEditFiles: Bool
    let updates: [WriteBatch]
    let deletions: [DeleteBatch]
    let hasUpload: Bool

    private static func updates(from chunkedParams: [SyncObject: [[[String: Any]]]],
                                version: Int,
                                libraryId: LibraryIdentifier) -> [WriteBatch] {
        var batches: [WriteBatch] = []

        let appendBatch: (SyncObject) -> Void = { object in
            if let params = chunkedParams[object] {
                batches.append(contentsOf: params.map({ WriteBatch(libraryId: libraryId, object: object,
                                                                   version: version, parameters: $0) }))
            }
        }

        appendBatch(.collection)
        appendBatch(.search)
        appendBatch(.item)
        appendBatch(.settings)

        return batches
    }

    private static func deletions(from chunkedKeys: [SyncObject: [[String]]],
                                  version: Int,
                                  libraryId: LibraryIdentifier) -> [DeleteBatch] {
        var batches: [DeleteBatch] = []

        let appendBatch: (SyncObject) -> Void = { object in
            if let keys = chunkedKeys[object] {
                batches.append(contentsOf: keys.map({ DeleteBatch(libraryId: libraryId, object: object,
                                                                  version: version, keys: $0) }))

            }
        }

        appendBatch(.collection)
        appendBatch(.search)
        appendBatch(.item)

        return batches
    }

    init(object: RCustomLibrary, userId: Int,
         chunkedUpdateParams: [SyncObject: [[[String: Any]]]],
         chunkedDeletionKeys: [SyncObject: [[String]]],
         hasUpload: Bool) {
        let type = object.type
        let versions = Versions(versions: object.versions)
        let maxVersion = versions.max

        self.identifier = .custom(type)
        self.name = type.libraryName
        self.versions = versions
        self.canEditMetadata = true
        self.canEditFiles = true
        self.hasUpload = hasUpload
        self.updates = LibraryData.updates(from: chunkedUpdateParams, version: maxVersion,
                                           libraryId: .custom(type))
        self.deletions = LibraryData.deletions(from: chunkedDeletionKeys, version: maxVersion,
                                               libraryId: .custom(type))
    }

    init(object: RGroup,
         chunkedUpdateParams: [SyncObject: [[[String: Any]]]],
         chunkedDeletionKeys: [SyncObject: [[String]]],
         hasUpload: Bool) {
        let versions = Versions(versions: object.versions)
        let maxVersion = versions.max

        self.identifier = .group(object.identifier)
        self.name = object.name
        self.versions = versions
        self.canEditMetadata = object.canEditMetadata
        self.canEditFiles = object.canEditFiles
        self.hasUpload = hasUpload
        self.updates = LibraryData.updates(from: chunkedUpdateParams, version: maxVersion,
                                           libraryId: .group(object.identifier))
        self.deletions = LibraryData.deletions(from: chunkedDeletionKeys, version: maxVersion,
                                               libraryId: .group(object.identifier))
    }

    // MARK: - Testing only

    init(identifier: LibraryIdentifier, name: String, versions: Versions,
         updates: [WriteBatch] = [], deletions: [DeleteBatch] = []) {
        self.identifier = identifier
        self.name = name
        self.versions = versions
        self.canEditMetadata = true
        self.canEditFiles = true
        self.updates = updates
        self.deletions = deletions
        self.hasUpload = false
    }
}
