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
}

final class UpdateDataSource: SyncUpdateDataSource {
    private let dbStorage: DbStorage

    init(dbStorage: DbStorage) {
        self.dbStorage = dbStorage
    }

    func updates(for library: SyncController.Library, versions: Versions) throws -> [SyncController.WriteBatch] {
        let coordinator = try self.dbStorage.createCoordinator()
        return (try self.updates(for: RCollection.self, object: .collection, library: library,
                                 version: versions.collections, coordinator: coordinator)) +
               (try self.updates(for: RSearch.self, object: .search, library: library,
                                 version: versions.searches, coordinator: coordinator))
    }

    private func updates<Obj: UpdatableObject>(for type: Obj.Type, object: SyncController.Object,
                                               library: SyncController.Library, version: Int,
                                               coordinator: DbCoordinator) throws -> [SyncController.WriteBatch] {
        let request = ReadChangedObjectsDbRequest<Obj>(libraryId: library.libraryId)
        let collections = try coordinator.perform(request: request)
        let parameters = Array(collections.compactMap({ $0.updateParameters }))
        return parameters.chunked(into: SyncController.WriteBatch.maxCount)
                         .map({ SyncController.WriteBatch(library: library, object: object,
                                                          version: version, parameters: $0) })
    }
}
