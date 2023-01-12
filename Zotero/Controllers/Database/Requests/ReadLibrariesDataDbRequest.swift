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
    let fetchUpdates: Bool
    let loadVersions: Bool
    let webDavEnabled: Bool

    var needsWrite: Bool { return false }

    func process(in database: Realm) throws -> [LibraryData] {
        var allLibraryData: [LibraryData] = []

        let separatedIds = self.identifiers.flatMap { self.separateTypes(in: $0) }

        var customLibraries = database.objects(RCustomLibrary.self)
        if let types = separatedIds?.custom {
            customLibraries = customLibraries.filter("type IN %@", types.map({ $0.rawValue }))
        }
        let customData = try customLibraries.map({ library -> LibraryData in
            let libraryId = LibraryIdentifier.custom(library.type)
            let versions = self.loadVersions ? Versions(versions: library.versions) : Versions.empty
            let version = versions.max
            let (updates, hasUpload) = try self.updates(for: libraryId, version: version, database: database)
            let deletions = try self.deletions(for: libraryId, version: version, database: database)
            let hasWebDavDeletions = !self.webDavEnabled ? false : !database.objects(RWebDavDeletion.self).isEmpty
            return LibraryData(identifier: libraryId, name: library.type.libraryName, versions: versions, canEditMetadata: true, canEditFiles: true, updates: updates, deletions: deletions,
                               hasUpload: hasUpload, hasWebDavDeletions: hasWebDavDeletions)
        })
        allLibraryData.append(contentsOf: customData)

        var groups = database.objects(RGroup.self).filter("isLocalOnly = false")
        if let groupIds = separatedIds?.group {
            groups = groups.filter("identifier IN %@", groupIds)
        }
        groups = groups.sorted(byKeyPath: "name")
        let groupData = try groups.map({ group -> LibraryData in
            let libraryId = LibraryIdentifier.group(group.identifier)
            let versions = self.loadVersions ? Versions(versions: group.versions) : Versions.empty
            let version = versions.max
            let (updates, hasUpload) = try self.updates(for: libraryId, version: version, database: database)
            let deletions = try self.deletions(for: libraryId, version: versions.max, database: database)
            return LibraryData(identifier: libraryId, name: group.name, versions: versions, canEditMetadata: group.canEditMetadata, canEditFiles: group.canEditFiles, updates: updates,
                               deletions: deletions, hasUpload: hasUpload, hasWebDavDeletions: false)
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

    func deletions(for libraryId: LibraryIdentifier, version: Int, database: Realm) throws -> [DeleteBatch] {
        guard self.fetchUpdates else { return [] }

        let collectionDeletions = (try ReadDeletedObjectsDbRequest<RCollection>(libraryId: libraryId).process(in: database))
                                                                                                     .map({ $0.key })
                                                                                                     .chunked(into: DeleteBatch.maxCount)
                                                                                                     .map({ DeleteBatch(libraryId: libraryId, object: .collection, version: version, keys: $0) })
        let searchDeletions = try ReadDeletedObjectsDbRequest<RSearch>(libraryId: libraryId).process(in: database)
                                                                                            .map({ $0.key })
                                                                                            .chunked(into: DeleteBatch.maxCount)
                                                                                            .map({ DeleteBatch(libraryId: libraryId, object: .search, version: version, keys: $0) })
        let itemDeletions = try ReadDeletedObjectsDbRequest<RItem>(libraryId: libraryId).process(in: database)
                                                                                        .map({ $0.key })
                                                                                        .chunked(into: DeleteBatch.maxCount)
                                                                                        .map({ DeleteBatch(libraryId: libraryId, object: .item, version: version, keys: $0) })

        return collectionDeletions + searchDeletions + itemDeletions
    }

    private func updates(for libraryId: LibraryIdentifier, version: Int, database: Realm) throws -> ([WriteBatch], Bool) {
        guard self.fetchUpdates else { return ([], false) }

        let collectionParams = try ReadUpdatedCollectionUpdateParametersDbRequest(libraryId: libraryId).process(in: database)
        let (itemParams, hasUpload) = try ReadUpdatedItemUpdateParametersDbRequest(libraryId: libraryId).process(in: database)
        let searchParams = try ReadUpdatedSearchUpdateParametersDbRequest(libraryId: libraryId).process(in: database)
        let settings = try ReadUpdatedSettingsUpdateParametersDbRequest(libraryId: libraryId).process(in: database)

        let batches = self.writeBatches(from: collectionParams, libraryId: libraryId, version: version, object: .collection) +
                      self.writeBatches(from: itemParams, libraryId: libraryId, version: version, object: .item) +
                      self.writeBatches(from: searchParams, libraryId: libraryId, version: version, object: .search) +
                      self.settingsWriteBatches(from: settings, libraryId: libraryId, version: version)

        return (batches, hasUpload)
    }

    private func writeBatches(from response: ReadUpdatedParametersResponse, libraryId: LibraryIdentifier, version: Int, object: SyncObject) -> [WriteBatch] {
        let chunks = response.parameters.chunked(into: WriteBatch.maxCount)
        var batches: [WriteBatch] = []

        for chunk in chunks {
            var uuids: [String: [String]] = [:]
            for params in chunk {
                guard let key = params["key"] as? String, let _uuids = response.changeUuids[key] else { continue }
                uuids[key] = _uuids
            }
            batches.append(WriteBatch(libraryId: libraryId, object: object, version: version, parameters: chunk, changeUuids: uuids))
        }

        return batches
    }

    private func settingsWriteBatches(from response: ReadUpdatedParametersResponse, libraryId: LibraryIdentifier, version: Int) -> [WriteBatch] {
        let chunks = response.parameters.chunked(into: WriteBatch.maxCount)
        var batches: [WriteBatch] = []

        for chunk in chunks {
            var uuids: [String: [String]] = [:]
            for params in chunk {
                guard let key = params.keys.first, let _uuids = response.changeUuids[key] else { continue }
                uuids[key] = _uuids
            }
            batches.append(WriteBatch(libraryId: libraryId, object: .settings, version: version, parameters: chunk, changeUuids: uuids))
        }

        return batches
    }
}
