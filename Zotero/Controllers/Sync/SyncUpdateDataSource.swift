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
        return (try self.collectionUpdates(for: library, coordinator: coordinator)) +
               (try self.itemUpdates(for: library, coordinator: coordinator)) +
               (try self.searchUpdates(for: library, coordinator: coordinator))
    }

    private func collectionUpdates(for library: SyncController.Library,
                                   coordinator: DbCoordinator) throws -> [SyncController.WriteBatch] {
        let request = ReadChangedCollectionsDbRequest(libraryId: library.libraryId)
        let collections = try coordinator.perform(request: request)
        let parameters = Array(collections.compactMap({ $0.writeParameters }))
        return parameters.chunked(into: SyncController.WriteBatch.maxCount)
                         .map({ SyncController.WriteBatch(library: library, object: .collection,
                                                          version: 0, parameters: $0) })
    }

    private func itemUpdates(for library: SyncController.Library,
                             coordinator: DbCoordinator) throws -> [SyncController.WriteBatch] {
        return []
    }

    private func searchUpdates(for library: SyncController.Library,
                               coordinator: DbCoordinator) throws -> [SyncController.WriteBatch] {
        return []
    }
}

extension RCollection {
    fileprivate var writeParameters: [String: Any]? {
        guard !self.changedFields.isEmpty else { return nil }
        var parameters: [String: Any] = [:]
        let changes = self.changedFields.split(separator: ",")
        changes.forEach { change in
            switch change {
            case "name":
                parameters["name"] = self.name
            case "parent":
                if let key = self.parent?.key {
                    parameters["parentCollection"] = key
                } else {
                    parameters["parentCollection"] = false
                }
            case "key":
                parameters["key"] = self.key
            case "version":
                parameters["version"] = self.version
            case "dateModified":
                parameters["dateModified"] = Formatter.iso8601.string(from: self.dateModified)
            default: break
            }
        }
        return parameters
    }
}
