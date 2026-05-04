//
//  DocumentWorkerJSHandler.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 30/12/25.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import CocoaLumberjackSwift
import RxSwift

enum DocumentWorkerData {
    case recognizerData(data: [String: Any])
    case fullText(data: [String: Any])
}

final class DocumentWorkerJSHandler {
    enum Action: String {
        case recognize = "pdf.getRecognizerData"
        case getFulltext = "pdf.getFulltext"
    }

    enum Error: Swift.Error {
        case engineNotLoaded
        case missingWorkFile
        case invalidMessage
        case unknownAction(String)
        case missingResource(String)
        case resourceReadFailed(String)
        case workerError(String)
        case missingData
    }

    var workFile: File?
    var shouldCacheWorkData: Bool = false
    let observable: PublishSubject<(workId: String, result: Result<DocumentWorkerData, Swift.Error>)>

    private let engine: DocumentWorkerJSEngine
    private let bundle: Bundle
    private let queue: DispatchQueue
    private let queueKey: DispatchSpecificKey<String>
    private let queueLabel: String
    private var nextMessageId: Int
    private var pending: [Int: (Result<Any, Swift.Error>) -> Void]
    private var loadError: Swift.Error?
    private var cachedWorkData: Data?

    init(bundle: Bundle = .main, warmUp: Bool = true) {
        queueLabel = "org.zotero.DocumentWorkerJSHandler.queue"
        queue = DispatchQueue(label: queueLabel)
        queueKey = DispatchSpecificKey<String>()
        queue.setSpecific(key: queueKey, value: queueLabel)
        self.bundle = bundle
        engine = DocumentWorkerJSEngine(bundle: bundle, queue: queue)
        observable = PublishSubject()
        nextMessageId = 1
        pending = [:]
        loadError = nil
        cachedWorkData = nil

        engine.onPostMessage = { [weak self] message, _ in
            guard let self else { return }
            if DispatchQueue.getSpecific(key: queueKey) == queueLabel {
                handlePostMessage(message: message)
            } else {
                queue.async { [weak self] in
                    self?.handlePostMessage(message: message)
                }
            }
        }
        engine.onLog = { message in
            DDLogInfo("DocumentWorkerJSHandler: JSLOG - \(message)")
        }
        engine.onException = { message in
            DDLogError("DocumentWorkerJSHandler: JSEXCEPTION - \(message)")
        }
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try engine.loadWorkerScripts()
                if warmUp {
                    // Warm-up call to the engine to avoid JIT/cold-start cost.
                    _ = try? engine.evaluate(script: "typeof self !== 'undefined' && typeof self.onmessage === 'function'")
                }
            } catch {
                DDLogError("DocumentWorkerJSHandler: failed to load worker scripts - \(error)")
                loadError = error
            }
        }
    }

    private func handlePostMessage(message: Any?) {
        guard let body = message as? [String: Any] else { return }

        if let responseId = body["responseID"] as? Int {
            if let error = body["error"] as? [String: Any], let name = error["name"] as? String {
                pending.removeValue(forKey: responseId)?(.failure(Error.workerError(name)))
            } else if let data = body["data"] {
                pending.removeValue(forKey: responseId)?(.success(data))
            } else {
                DDLogError("DocumentWorkerJSHandler: response \(responseId) missing data")
                pending.removeValue(forKey: responseId)?(.failure(Error.missingData))
            }
            return
        }

        guard let id = body["id"] as? Int, let action = body["action"] as? String else { return }
        guard let data = body["data"] else {
            respondWithError(to: engine, id: id, message: "missing data")
            return
        }

        switch action {
        case "FetchData":
            guard let path = data as? String else {
                respondWithError(to: engine, id: id, message: "missing data path")
                return
            }
            respondWithBundledWorkerData(to: engine, path: path, responseId: id)

        default:
            respondWithError(to: engine, id: id, message: "unknown action \(action)")
        }

        func respondWithError(to engine: DocumentWorkerJSEngine, id: Int, message: String) {
            let response = engine.makeObject()
            let error = engine.makeObject()
            error.setValue(message, forProperty: "name")
            response.setValue(id, forProperty: "responseID")
            response.setValue(error, forProperty: "error")
            do {
                try engine.postToWorker(response)
            } catch {
                DDLogError("DocumentWorkerJSHandler: failed to respond with error to JS engine - \(error)")
            }
        }

        func respondWithBundledWorkerData(to engine: DocumentWorkerJSEngine, path: String, responseId: Int) {
            let normalizedPath = path.replacingOccurrences(of: "\\", with: "/")
            let components = normalizedPath.split(separator: "/", omittingEmptySubsequences: false)
            let hasUnsafeComponent = components.contains { $0.isEmpty || $0 == ".." }
            guard !normalizedPath.isEmpty,
                  !normalizedPath.hasPrefix("/"),
                  !hasUnsafeComponent else {
                respondWithError(to: engine, id: responseId, message: "invalid data path \(path)")
                return
            }

            let nsPath = normalizedPath as NSString
            let resourceName = nsPath.lastPathComponent
            guard !resourceName.isEmpty, resourceName != "." else {
                respondWithError(to: engine, id: responseId, message: "invalid data path \(path)")
                return
            }
            let directory = nsPath.deletingLastPathComponent
            let subdirectory: String
            if directory.isEmpty || directory == "." {
                subdirectory = "Bundled/document_worker"
            } else {
                subdirectory = "Bundled/document_worker/\(directory)"
            }

            guard let url = bundle.url(forResource: resourceName, withExtension: nil, subdirectory: subdirectory) else {
                respondWithError(to: engine, id: responseId, message: "missing data \(path)")
                return
            }
            guard let data = try? Data(contentsOf: url) else {
                respondWithError(to: engine, id: responseId, message: "failed to read data \(path)")
                return
            }
            guard let bytes = engine.makeUint8Array(from: data) else {
                respondWithError(to: engine, id: responseId, message: "failed to create data \(path)")
                return
            }

            let response = engine.makeObject()
            response.setValue(responseId, forProperty: "responseID")
            response.setValue(bytes, forProperty: "data")
            do {
                try engine.postToWorker(response)
            } catch {
                DDLogError("DocumentWorkerJSHandler: failed to respond to data request - \(error)")
            }
        }
    }

    func recognize(workId: String) {
        startWork(action: .recognize, pages: nil, workId: workId)
    }

    func getFullText(pages: [Int]?, workId: String) {
        startWork(action: .getFulltext, pages: pages, workId: workId)
    }

    private func startWork(action: Action, pages: [Int]?, workId: String) {
        queue.async { [weak self] in
            guard let self else { return }
            var deferredError: Swift.Error?
            defer {
                if let error = deferredError {
                    DDLogError("DocumentWorkerJSHandler: failed to start work - \(error)")
                    observable.on(.next((workId: workId, result: .failure(error))))
                }
            }
            if let loadError {
                deferredError = loadError
                return
            }
            guard let workFile else {
                deferredError = Error.missingWorkFile
                return
            }
            let url = workFile.createUrl()
            do {
                let data: Data
                if shouldCacheWorkData {
                    if let cachedWorkData {
                        data = cachedWorkData
                    } else {
                        data = try Data(contentsOf: url, options: [.mappedIfSafe])
                        cachedWorkData = data
                    }
                } else {
                    data = try Data(contentsOf: url, options: [.mappedIfSafe])
                    cachedWorkData = nil
                }
                guard let buffer = engine.makeArrayBuffer(from: data) else {
                    throw Error.invalidMessage
                }

                let message = engine.makeObject()
                message.setValue(nextMessageId, forProperty: "id")
                message.setValue(action.rawValue, forProperty: "action")

                let dataObject = engine.makeObject()
                dataObject.setValue(buffer, forProperty: "buf")
                if let pages {
                    dataObject.setValue(pages, forProperty: "pageIndexes")
                }
                message.setValue(dataObject, forProperty: "data")

                let messageId = nextMessageId
                nextMessageId += 1

                pending[messageId] = { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(let payload):
                        guard let data = payload as? [String: Any] else {
                            observable.on(.next((workId: workId, result: .failure(Error.invalidMessage))))
                            return
                        }
                        switch action {
                        case .recognize:
                            observable.on(.next((workId: workId, result: .success(.recognizerData(data: data)))))

                        case .getFulltext:
                            observable.on(.next((workId: workId, result: .success(.fullText(data: data)))))
                        }

                    case .failure(let error):
                        observable.on(.next((workId: workId, result: .failure(error))))
                    }
                }

                try engine.postToWorker(message)
            } catch {
                deferredError = error
            }
        }
    }
}
