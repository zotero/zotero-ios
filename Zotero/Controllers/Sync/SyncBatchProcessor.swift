//
//  SyncBatchProcessor.swift
//  Zotero
//
//  Created by Michal Rentka on 08/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

typealias SyncBatchResponse = (failedIds: [String], parsingErrors: [Error], conflicts: [StoreItemsError])

class SyncBatchProcessor {
    private let storageQueue: DispatchQueue
    private let requestQueue: OperationQueue
    private let batches: [DownloadBatch]
    private let userId: Int
    private let progress: (Int) -> Void
    private let completion: (Result<SyncBatchResponse, Error>) -> Void
    private unowned let apiClient: ApiClient
    private unowned let dbStorage: DbStorage
    private unowned let fileStorage: FileStorage
    private unowned let schemaController: SchemaController
    private unowned let dateParser: DateParser

    private var failedIds: [String]
    private var parsingErrors: [Error]
    private var itemConflicts: [StoreItemsError]
    private var isFinished: Bool
    private var processedCount: Int

    // MARK: - Lifecycle

    init(batches: [DownloadBatch], userId: Int, apiClient: ApiClient, dbStorage: DbStorage,
         fileStorage: FileStorage, schemaController: SchemaController, dateParser: DateParser,
         progress: @escaping (Int) -> Void, completion: @escaping (Result<SyncBatchResponse, Error>) -> Void) {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .userInteractive

        self.storageQueue = DispatchQueue(label: "org.zotero.SyncBatchDownloader.StorageQueue",
                                          qos: .userInteractive, attributes: .concurrent)
        self.batches = batches
        self.userId = userId
        self.apiClient = apiClient
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.schemaController = schemaController
        self.dateParser = dateParser
        self.progress = progress
        self.completion = completion
        self.requestQueue = queue
        self.failedIds = []
        self.parsingErrors = []
        self.itemConflicts = []
        self.isFinished = false
        self.processedCount = 0
    }

    deinit {
        self.requestQueue.cancelAllOperations()
    }

    // MARK: - Actions

    func start() {
        let operations = self.batches.map { batch -> ApiOperation in
            let keysString = batch.keys.map({ "\($0)" }).joined(separator: ",")
            let request = ObjectsRequest(libraryId: batch.libraryId, userId: self.userId, objectType: batch.object, keys: keysString)
            return self.apiClient.operation(from: request, queue: self.storageQueue) { [weak self] result in
                self?.process(result: result, batch: batch)
            }
        }
        self.requestQueue.addOperations(operations, waitUntilFinished: false)
    }

    private func process(result: Result<(Data, ResponseHeaders), Error>, batch: DownloadBatch) {
        guard !self.isFinished else { return }

        switch result {
        case .success(let response):
            self.process(data: response.0, headers: response.1, batch: batch)
        case .failure(let error):
            self.cancel(with: error)
        }
    }

    private func process(data: Data, headers: ResponseHeaders, batch: DownloadBatch) {
        guard !self.isFinished else { return }

        if batch.version != headers.lastModifiedVersion {
            self.cancel(with: SyncError.versionMismatch)
            return
        }

        do {
            let response = try self.sync(data: data, libraryId: batch.libraryId, object: batch.object, userId: self.userId, expectedKeys: batch.keys)
            self.progress(batch.keys.count)
            self.finish(response: response)
        } catch let error {
            self.cancel(with: error)
        }
    }

    private func finish(response: SyncBatchResponse) {
        guard !self.isFinished else { return }

        self.storageQueue.async(flags: .barrier) { [weak self] in
            guard let `self` = self else { return }

            self.failedIds.append(contentsOf: response.failedIds)
            self.parsingErrors.append(contentsOf: response.parsingErrors)
            self.itemConflicts.append(contentsOf: response.conflicts)

            self.processedCount += 1

            if self.processedCount == self.batches.count {
                self.completion(.success((self.failedIds, self.parsingErrors, self.itemConflicts)))
                self.isFinished = true
            }
        }
    }

    private func cancel(with error: Error) {
        self.storageQueue.async(flags: .barrier) { [weak self] in
            guard let `self` = self else { return }

            self.requestQueue.cancelAllOperations()
            self.isFinished = true
            self.completion(.failure(error))
        }
    }

    private func sync(data: Data, libraryId: LibraryIdentifier, object: SyncObject, userId: Int, expectedKeys: [String]) throws -> SyncBatchResponse {
        let coordinator = try self.dbStorage.createCoordinator()

        switch object {
        case .collection:
            let decoded = try JSONDecoder().decode(CollectionsResponse.self, from: data)

            // Cache JSONs locally for later use (in CR)
            self.storeIndividualCodableJsonObjects(from: decoded.collections, type: .collection, libraryId: libraryId)

            try coordinator.performInAutoreleasepoolIfNeeded {
                try coordinator.perform(request: StoreCollectionsDbRequest(response: decoded.collections))
            }
            let failedKeys = expectedKeys.filter({ key in !decoded.collections.contains(where: { $0.key == key }) })
            return (failedKeys, decoded.errors, [])

        case .search:
            let decoded = try JSONDecoder().decode(SearchesResponse.self, from: data)

            // Cache JSONs locally for later use (in CR)
            self.storeIndividualCodableJsonObjects(from: decoded.searches, type: .search, libraryId: libraryId)

            try coordinator.performInAutoreleasepoolIfNeeded {
                try coordinator.perform(request: StoreSearchesDbRequest(response: decoded.searches))
            }
            let failedKeys = expectedKeys.filter({ key in !decoded.searches.contains(where: { $0.key == key }) })
            return (failedKeys, decoded.errors, [])

        case .item, .trash:
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
            let (items, objects, errors) = try ItemResponse.decode(response: jsonObject, schemaController: self.schemaController)

            // Cache JSONs locally for later use (in CR)
            self.storeIndividualItem(jsonObjects: objects, libraryId: libraryId)

            // BETA: - forcing preferRemoteData to true for beta, it should be false here so that we report conflicts
            let conflicts = try coordinator.performInAutoreleasepoolIfNeeded {
                try coordinator.perform(request: StoreItemsDbRequest(response: items, schemaController: self.schemaController,
                                                                     dateParser: self.dateParser, preferRemoteData: true))
            }
            let failedKeys = expectedKeys.filter({ key in !items.contains(where: { $0.key == key }) })

            return (failedKeys, errors, conflicts)
        }
    }

    private func storeIndividualItem(jsonObjects: [[String: Any]], libraryId: LibraryIdentifier) {
        for object in jsonObjects {
            guard let key = object["key"] as? String else { continue }
            do {
                let data = try JSONSerialization.data(withJSONObject: object, options: [])
                let file = Files.jsonCacheFile(for: .item, libraryId: libraryId, key: key)
                try self.fileStorage.write(data, to: file, options: .atomicWrite)
            } catch let error {
                DDLogError("SyncBatchProcessor: can't encode/write item - \(error)\n\(object)")
            }
        }
    }

    private func storeIndividualCodableJsonObjects<Object: KeyedResponse&Codable>(from objects: [Object],
                                                                                  type: SyncObject,
                                                                                  libraryId: LibraryIdentifier) {
        for object in objects {
            do {
                let data = try JSONEncoder().encode(object)
                let file = Files.jsonCacheFile(for: type, libraryId: libraryId, key: object.key)
                try self.fileStorage.write(data, to: file, options: .atomicWrite)
            } catch let error {
                DDLogError("SyncBatchProcessor: can't encode/write object - \(error)\n\(object)")
            }
        }
    }
}
