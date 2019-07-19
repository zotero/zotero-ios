//
//  ReadLibrariesDataDbRequest.swift
//  Zotero
//
//  Created by Michal Rentka on 05/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

struct ReadLibrariesDataDbRequest: DbResponseRequest {
    typealias Response = [LibraryData]

    let identifiers: [LibraryIdentifier]?

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> [LibraryData] {
        var allLibraryData: [LibraryData] = []

        let userId = try ReadUserDbRequest().process(in: database).identifier
        let separatedIds = self.identifiers.flatMap { self.separateTypes(in: $0) }

        var customLibraries = database.objects(RCustomLibrary.self)
        if let types = separatedIds?.custom {
            customLibraries = customLibraries.filter("rawType IN %@", types.map({ $0.rawValue }))
        }
        let customData = try customLibraries.map({ library -> LibraryData in
            let libraryId = LibraryIdentifier.custom(library.type)
            return LibraryData(object: library, userId: userId,
                               chunkedUpdateParams: try self.updates(for: libraryId, database: database),
                               chunkedDeletionKeys: try self.deletions(for: libraryId, database: database))
        })
        allLibraryData.append(contentsOf: customData)

        var groups = database.objects(RGroup.self).filter("isLocalOnly = false")
        if let groupIds = separatedIds?.group {
            groups = groups.filter("identifier IN %@", groupIds)
        }
        let groupData = try groups.map({ group -> LibraryData in
            let libraryId = LibraryIdentifier.group(group.identifier)
            return LibraryData(object: group,
                               chunkedUpdateParams: try self.updates(for: libraryId, database: database),
                               chunkedDeletionKeys: try self.deletions(for: libraryId, database: database))
        })
        allLibraryData.append(contentsOf: groupData)

        return allLibraryData
    }

    private func separateTypes(in identifiers: [LibraryIdentifier]) -> (custom: [RCustomLibraryType], group: [Int]) {
        var custom: [RCustomLibraryType] = []
        var group: [Int] = []
        identifiers.forEach { identifier in
            switch identifier {
            case .custom(let type):
                custom.append(type)
            case .group(let groupId):
                group.append(groupId)
            }
        }
        return (custom, group)
    }

    func deletions(for libraryId: LibraryIdentifier, database: Realm) throws -> [SyncController.Object: [[String]]] {
        let chunkSize = SyncController.DeleteBatch.maxCount
        return [.collection: try ReadDeletedObjectsDbRequest<RCollection>(libraryId: libraryId).process(in: database).map({ $0.key }).chunked(into: chunkSize),
                .search: try ReadDeletedObjectsDbRequest<RSearch>(libraryId: libraryId).process(in: database).map({ $0.key }).chunked(into: chunkSize),
                .item: try ReadDeletedObjectsDbRequest<RItem>(libraryId: libraryId).process(in: database).map({ $0.key }).chunked(into: chunkSize)]
    }

    private func updates(for libraryId: LibraryIdentifier, database: Realm) throws -> [SyncController.Object: [[[String: Any]]]] {
        let chunkSize = SyncController.WriteBatch.maxCount
        return [.collection: try ReadUpdatedCollectionUpdateParametersDbRequest(libraryId: libraryId).process(in: database).chunked(into: chunkSize),
                .search: try ReadUpdatedSearchUpdateParametersDbRequest(libraryId: libraryId).process(in: database).chunked(into: chunkSize),
                .item: try ReadUpdatedItemUpdateParametersDbRequest(libraryId: libraryId).process(in: database).chunked(into: chunkSize)]
    }
}
