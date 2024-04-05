//
//  PerformDeletionsSyncAction.swift
//  Zotero
//
//  Created by Michal Rentka on 09.02.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import RxSwift

struct PerformDeletionsSyncAction: SyncAction {
    typealias Result = [(String, String)]

    private static let batchSize = 500
    let libraryId: LibraryIdentifier
    let collections: [String]
    let items: [String]
    let searches: [String]
    let tags: [String]
    let conflictMode: PerformItemDeletionsDbRequest.ConflictResolutionMode
    unowned let dbStorage: DbStorage
    let queue: DispatchQueue

    var result: Single<[(String, String)]> {
        return Single.create { subscriber -> Disposable in
            do {
                let hasCollections = try dbStorage.perform(request: CountObjectsDbRequest<RCollection>(), on: queue) > 0
                if hasCollections {
                    try batch(values: collections, batchSize: Self.batchSize) { batch in
                        try dbStorage.perform(request: PerformCollectionDeletionsDbRequest(libraryId: libraryId, keys: batch), on: queue)
                    }
                }

                let hasSearches = try dbStorage.perform(request: CountObjectsDbRequest<RSearch>(), on: queue) > 0
                if hasSearches {
                    try batch(values: searches, batchSize: Self.batchSize) { batch in
                        try dbStorage.perform(request: PerformSearchDeletionsDbRequest(libraryId: libraryId, keys: batch), on: queue)
                    }
                }

                let hasTags = try dbStorage.perform(request: CountObjectsDbRequest<RTag>(), on: queue) > 0
                if hasTags {
                    try batch(values: tags, batchSize: Self.batchSize) { batch in
                        try dbStorage.perform(request: PerformTagDeletionsDbRequest(libraryId: libraryId, names: batch), on: queue)
                    }
                }

                var conflicts: [(String, String)] = []
                let hasItems = try dbStorage.perform(request: CountObjectsDbRequest<RItem>(), on: queue) > 0
                if hasItems {
                    try batch(values: items, batchSize: Self.batchSize) { batch in
                        let batchConflicts = try dbStorage.perform(request: PerformItemDeletionsDbRequest(libraryId: libraryId, keys: batch, conflictMode: conflictMode), on: queue)
                        conflicts.append(contentsOf: batchConflicts)
                    }
                }

                subscriber(.success(conflicts))
            } catch let error {
                subscriber(.failure(error))
            }

            return Disposables.create()
        }
    }

    private func batch(values: [String], batchSize: Int, deleteValues: ([String]) throws -> Void) throws {
        guard !values.isEmpty else { return }
        var count = 0
        while count < values.count {
            let upperLimit = min(count + batchSize, values.count)
            let slice = values[count..<upperLimit]
            try deleteValues(Array(slice))
            count = upperLimit
        }
    }
}
