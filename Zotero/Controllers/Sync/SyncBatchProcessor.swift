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

typealias SyncBatchResponse = (failedIds: [String], parsingErrors: [Error], conflicts: [StoreItemsResponse.Error], changedAttachments: [StoreItemsResponse.AttachmentData])

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
    private var changedAttachments: [StoreItemsResponse.AttachmentData]
    private var isFinished: Bool
    private var processedCount: Int

    // MARK: - Lifecycle

    init(
        batches: [DownloadBatch],
        userId: Int,
        apiClient: ApiClient,
        dbStorage: DbStorage,
        fileStorage: FileStorage,
        schemaController: SchemaController,
        dateParser: DateParser,
        progress: @escaping (Int) -> Void,
        completion: @escaping (Result<SyncBatchResponse, Error>) -> Void
    ) {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .userInteractive
        storageQueue = DispatchQueue(label: "org.zotero.SyncBatchDownloader.StorageQueue", qos: .userInteractive)
        self.batches = batches
        self.userId = userId
        self.apiClient = apiClient
        self.dbStorage = dbStorage
        self.fileStorage = fileStorage
        self.schemaController = schemaController
        self.dateParser = dateParser
        self.progress = progress
        self.completion = completion
        requestQueue = queue
        failedIds = []
        parsingErrors = []
        itemConflicts = []
        changedAttachments = []
        isFinished = false
        processedCount = 0
    }

    deinit {
        requestQueue.cancelAllOperations()
    }

    // MARK: - Actions

    func start() {
        let operations = batches.map { batch -> ApiOperation in
            let keysString = batch.keys.map({ "\($0)" }).joined(separator: ",")
            let request = ObjectsRequest(libraryId: batch.libraryId, userId: userId, objectType: batch.object, keys: keysString)
            return ApiOperation(apiRequest: request, apiClient: apiClient, responseQueue: storageQueue) { [weak self] result in
                self?.process(result: result, batch: batch)
            }
        }
        requestQueue.addOperations(operations, waitUntilFinished: false)
    }

    private func process(result: Result<(Data?, HTTPURLResponse), Error>, batch: DownloadBatch) {
        guard !isFinished else { return }

        switch result {
        case .success(let response):
            if let data = response.0 {
                process(data: data, headers: response.1.allHeaderFields, batch: batch)
            } else {
                cancel(with: AFError.responseSerializationFailed(reason: .inputDataNilOrZeroLength))
            }

        case .failure(let error):
            cancel(with: error)
        }
    }

    private func process(data: Data, headers: ResponseHeaders, batch: DownloadBatch) {
        guard !isFinished else { return }

        if batch.version != headers.lastModifiedVersion {
            cancel(with: SyncError.NonFatal.versionMismatch(batch.libraryId))
            return
        }

        do {
            let response = try sync(data: data, libraryId: batch.libraryId, object: batch.object, userId: userId, expectedKeys: batch.keys)
            progress(batch.keys.count)
            finish(response: response)
        } catch let error {
            cancel(with: error)
        }
    }

    private func finish(response: SyncBatchResponse) {
        guard !isFinished else { return }

        failedIds.append(contentsOf: response.failedIds)
        parsingErrors.append(contentsOf: response.parsingErrors)
        itemConflicts.append(contentsOf: response.conflicts)
        changedAttachments.append(contentsOf: response.changedAttachments)
        processedCount += 1

        if processedCount == batches.count {
            completion(.success((failedIds, parsingErrors, itemConflicts, changedAttachments)))
            isFinished = true
        }
    }

    private func cancel(with error: Error) {
        requestQueue.cancelAllOperations()
        isFinished = true
        completion(.failure(error))
    }

    private func sync(data: Data, libraryId: LibraryIdentifier, object: SyncObject, userId: Int, expectedKeys: [String]) throws -> SyncBatchResponse {
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments)

        switch object {
        case .collection:
            let (collections, objects, errors) = try Parsing.parse(response: jsonObject, createResponse: { try CollectionResponse(response: $0) })

            // Cache JSONs locally for later use (in CR)
            storeIndividualObjects(from: objects, type: .collection, libraryId: libraryId)

            try dbStorage.perform(request: StoreCollectionsDbRequest(response: collections), on: storageQueue)

            let failedKeys = failedKeys(from: expectedKeys, parsedKeys: collections.map({ $0.key }), errors: errors)
            return (failedKeys, errors, [], [])

        case .search:
            let (searches, objects, errors) = try Parsing.parse(response: jsonObject, createResponse: { try SearchResponse(response: $0) })

            // Cache JSONs locally for later use (in CR)
            storeIndividualObjects(from: objects, type: .search, libraryId: libraryId)

            try dbStorage.perform(request: StoreSearchesDbRequest(response: searches), on: storageQueue)

            let failedKeys = failedKeys(from: expectedKeys, parsedKeys: searches.map({ $0.key }), errors: errors)
            return (failedKeys, errors, [], [])

        case .item, .trash:
            let (items, objects, errors) = try Parsing.parse(response: jsonObject, createResponse: { try ItemResponse(response: $0, schemaController: schemaController) })

            // Cache JSONs locally for later use (in CR)
            storeIndividualObjects(from: objects, type: .item, libraryId: libraryId)

            // BETA: - forcing preferResponseData to true for beta, it should be false here so that we report conflicts
            let request = StoreItemsDbResponseRequest(responses: items, schemaController: schemaController, dateParser: dateParser, preferResponseData: true, denyIncorrectCreator: true)
            let response = try dbStorage.perform(request: request, on: storageQueue, invalidateRealm: true)
            let failedKeys = failedKeys(from: expectedKeys, parsedKeys: items.map({ $0.key }), errors: errors)

            renameExistingFiles(changes: response.changedFilenames, libraryId: libraryId)

            return (failedKeys, errors, response.conflicts, response.changedAttachments)

        case .settings:
            return ([], [], [], [])
        }

        func renameExistingFiles(changes: [StoreItemsResponse.FilenameChange], libraryId: LibraryIdentifier) {
            for change in changes {
                let oldFile = Files.attachmentFile(in: libraryId, key: change.key, filename: change.oldName, contentType: change.contentType)

                guard fileStorage.has(oldFile) else { continue }

                let newFile = Files.attachmentFile(in: libraryId, key: change.key, filename: change.newName, contentType: change.contentType)

                do {
                    try fileStorage.move(from: oldFile, to: newFile)
                } catch let error {
                    DDLogWarn("SyncBatchProcessor: can't rename file - \(error)")
                    // If it can't be moved, at least delete the old one. It'll have to be re-downloaded anyway.
                    try? fileStorage.remove(oldFile)
                }
            }
        }

        func failedKeys(from expectedKeys: [String], parsedKeys: [String], errors: [Error]) -> [String] {
            // Keys that were not successfully parsed will be marked for resync so that the sync process can continue without them for now.
            // Filter out parsed keys.
            return expectedKeys.filter({ !parsedKeys.contains($0) })
        }

        func storeIndividualObjects(from jsonObjects: [[String: Any]], type: SyncObject, libraryId: LibraryIdentifier) {
            for object in jsonObjects {
                guard let key = object["key"] as? String else { continue }
                do {
                    let data = try JSONSerialization.data(withJSONObject: object, options: [])
                    let file = Files.jsonCacheFile(for: type, libraryId: libraryId, key: key)
                    try fileStorage.write(data, to: file, options: .atomicWrite)
                } catch let error {
                    DDLogError("SyncBatchProcessor: can't encode/write item - \(error)\n\(object)")
                }
            }
        }
    }
}
