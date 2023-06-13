//
//  SyncBatchProcessor.swift
//  Zotero
//
//  Created by Michal Rentka on 08/06/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import Alamofire
import CocoaLumberjackSwift

typealias SyncBatchResponse = (failedIds: [String], parsingErrors: [Error], conflicts: [StoreItemsResponse.Error])

final class SyncBatchProcessor {
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
    private var itemConflicts: [StoreItemsResponse.Error]
    private var isFinished: Bool
    private var processedCount: Int

    // MARK: - Lifecycle

    init(batches: [DownloadBatch], userId: Int, apiClient: ApiClient, dbStorage: DbStorage, fileStorage: FileStorage, schemaController: SchemaController, dateParser: DateParser,
         progress: @escaping (Int) -> Void, completion: @escaping (Result<SyncBatchResponse, Error>) -> Void) {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .userInteractive

        self.storageQueue = DispatchQueue(label: "org.zotero.SyncBatchDownloader.StorageQueue", qos: .userInteractive)
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

    private func process(result: Result<(Data?, HTTPURLResponse), Error>, batch: DownloadBatch) {
        guard !self.isFinished else { return }

        switch result {
        case .success(let response):
            if let data = response.0 {
                self.process(data: data, headers: response.1.allHeaderFields, batch: batch)
            } else {
                self.cancel(with: AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength))
            }

        case .failure(let error):
            self.cancel(with: error)
        }
    }

    private func process(data: Data, headers: ResponseHeaders, batch: DownloadBatch) {
        guard !self.isFinished else { return }

        if batch.version != headers.lastModifiedVersion {
            self.cancel(with: SyncError.NonFatal.versionMismatch(batch.libraryId))
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

        self.failedIds.append(contentsOf: response.failedIds)
        self.parsingErrors.append(contentsOf: response.parsingErrors)
        self.itemConflicts.append(contentsOf: response.conflicts)

        self.processedCount += 1

        if self.processedCount == self.batches.count {
            self.completion(.success((self.failedIds, self.parsingErrors, self.itemConflicts)))
            self.isFinished = true
        }
    }

    private func cancel(with error: Error) {
        self.requestQueue.cancelAllOperations()
        self.isFinished = true
        self.completion(.failure(error))
    }

    private func sync(data: Data, libraryId: LibraryIdentifier, object: SyncObject, userId: Int, expectedKeys: [String]) throws -> SyncBatchResponse {
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments)

        switch object {
        case .collection:
            let (collections, objects, errors) = try Parsing.parse(response: jsonObject, createResponse: { try CollectionResponse(response: $0) })

            // Cache JSONs locally for later use (in CR)
            self.storeIndividualObjects(from: objects, type: .collection, libraryId: libraryId)

            try self.dbStorage.perform(request: StoreCollectionsDbRequest(response: collections), on: self.storageQueue)

            let failedKeys = self.failedKeys(from: expectedKeys, parsedKeys: collections.map({ $0.key }), errors: errors)
            return (failedKeys, errors, [])

        case .search:
            let (searches, objects, errors) = try Parsing.parse(response: jsonObject, createResponse: { try SearchResponse(response: $0) })

            // Cache JSONs locally for later use (in CR)
            self.storeIndividualObjects(from: objects, type: .search, libraryId: libraryId)

            try self.dbStorage.perform(request: StoreSearchesDbRequest(response: searches), on: self.storageQueue)

            let failedKeys = self.failedKeys(from: expectedKeys, parsedKeys: searches.map({ $0.key }), errors: errors)
            return (failedKeys, errors, [])

        case .item, .trash:
            let (items, objects, errors) = try Parsing.parse(response: jsonObject, createResponse: { try ItemResponse(response: $0, schemaController: self.schemaController) })

            // Cache JSONs locally for later use (in CR)
            self.storeIndividualObjects(from: objects, type: .item, libraryId: libraryId)

            // BETA: - forcing preferResponseData to true for beta, it should be false here so that we report conflicts
            let request = StoreItemsDbResponseRequest(responses: items, schemaController: self.schemaController, dateParser: self.dateParser, preferResponseData: true)
            let response = try self.dbStorage.perform(request: request, on: self.storageQueue, invalidateRealm: true)
            let failedKeys = self.failedKeys(from: expectedKeys, parsedKeys: items.map({ $0.key }), errors: errors)

            self.renameExistingFiles(changes: response.changedFilenames, libraryId: libraryId)

            return (failedKeys, errors, response.conflicts)

        case .settings:
            return ([], [], [])
        }
    }

    private func failedKeys(from expectedKeys: [String], parsedKeys: [String], errors: [Error]) -> [String] {
        // Keys that were not successfully parsed will be marked for resync so that the sync process can continue without them for now.
        // Filter out parsed keys.
        return expectedKeys.filter({ !parsedKeys.contains($0) })
    }

    private func renameExistingFiles(changes: [StoreItemsResponse.FilenameChange], libraryId: LibraryIdentifier) {
        for change in changes {
            let oldFile = Files.attachmentFile(in: libraryId, key: change.key, filename: change.oldName, contentType: change.contentType)

            guard self.fileStorage.has(oldFile) else { continue }

            let newFile = Files.attachmentFile(in: libraryId, key: change.key, filename: change.newName, contentType: change.contentType)

            do {
                try self.fileStorage.move(from: oldFile, to: newFile)
            } catch let error {
                DDLogWarn("SyncBatchProcessor: can't rename file - \(error)")
                // If it can't be moved, at least delete the old one. It'll have to be re-downloaded anyway.
                try? self.fileStorage.remove(oldFile)
            }
        }
    }

    private func storeIndividualObjects(from jsonObjects: [[String: Any]], type: SyncObject, libraryId: LibraryIdentifier) {
        for object in jsonObjects {
            guard let key = object["key"] as? String else { continue }
            do {
                let data = try JSONSerialization.data(withJSONObject: object, options: [])
                let file = Files.jsonCacheFile(for: type, libraryId: libraryId, key: key)
                try self.fileStorage.write(data, to: file, options: .atomicWrite)
            } catch let error {
                DDLogError("SyncBatchProcessor: can't encode/write item - \(error)\n\(object)")
            }
        }
    }
}
