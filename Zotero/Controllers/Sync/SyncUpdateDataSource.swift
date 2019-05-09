//
//  SyncUpdateDataSource.swift
//  Zotero
//
//  Created by Michal Rentka on 08/03/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RealmSwift

protocol SyncUpdateDataSource: class {
    func updates(for library: SyncController.Library, versions: Versions) throws -> [SyncController.WriteBatch]
    func deletions(for library: SyncController.Library, versions: Versions) throws -> [SyncController.DeleteBatch]
}

final class UpdateDataSource: SyncUpdateDataSource {
    private let dbStorage: DbStorage

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
    }

    func deletions(for library: SyncController.Library, versions: Versions) throws -> [SyncController.DeleteBatch] {
        let coordinator = try self.dbStorage.createCoordinator()
        let maxVersion = versions.max
        return (try self.deletions(object: .collection, library: library,
                                   version: maxVersion, coordinator: coordinator)) +
                (try self.deletions(object: .search, library: library,
                                    version: maxVersion, coordinator: coordinator)) +
                (try self.deletions(object: .item, library: library,
                                    version: maxVersion, coordinator: coordinator))
    }

    private func deletions(object: SyncController.Object, library: SyncController.Library,
                           version: Int, coordinator: DbCoordinator) throws -> [SyncController.DeleteBatch] {
        let keys: [String]
        switch object {
        case .collection:
            let request = ReadDeletedObjectsDbRequest<RCollection>(libraryId: library.libraryId)
            keys = (try coordinator.perform(request: request)).map({ $0.key })
        case .search:
            let request = ReadDeletedObjectsDbRequest<RSearch>(libraryId: library.libraryId)
            keys = (try coordinator.perform(request: request)).map({ $0.key })
        case .item, .trash:
            let request = ReadDeletedObjectsDbRequest<RItem>(libraryId: library.libraryId)
            keys = (try coordinator.perform(request: request)).map({ $0.key })
        case .group, .tag:
            fatalError("UpdateDataSource: Deleting unsupported object type")
        }
        return keys.chunked(into: SyncController.DeleteBatch.maxCount)
                   .map({ SyncController.DeleteBatch(library: library, object: object, version: version, keys: $0) })
    }

    func updates(for library: SyncController.Library, versions: Versions) throws -> [SyncController.WriteBatch] {
        let coordinator = try self.dbStorage.createCoordinator()
        let maxVersion = versions.max
        return (try self.updates(object: .collection, library: library,
                                 version: maxVersion, coordinator: coordinator)) +
               (try self.updates(object: .search, library: library,
                                 version: maxVersion, coordinator: coordinator)) +
               (try self.updates(object: .item, library: library,
                                 version: maxVersion, coordinator: coordinator))
    }

    private func updates(object: SyncController.Object, library: SyncController.Library, version: Int,
                         coordinator: DbCoordinator) throws -> [SyncController.WriteBatch] {
        let parameters: [[String: Any]]
        switch object {
        case .collection:
            let request = ReadChangedCollectionUpdateParametersDbRequest(libraryId: library.libraryId)
            parameters = try coordinator.perform(request: request)
        case .search:
            let request = ReadChangedSearchUpdateParametersDbRequest(libraryId: library.libraryId)
            parameters = try coordinator.perform(request: request)
        case .item, .trash:
            let request = ReadChangedItemUpdateParametersDbRequest(libraryId: library.libraryId)
            parameters = try coordinator.perform(request: request)
        case .group, .tag:
            fatalError("UpdateDataSource: Updating unsupported object type")
        }
        return parameters.chunked(into: SyncController.WriteBatch.maxCount)
                         .map({ SyncController.WriteBatch(library: library, object: object,
                                                          version: version, parameters: $0) })
    }
}
