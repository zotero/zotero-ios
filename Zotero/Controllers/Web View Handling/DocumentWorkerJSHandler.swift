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

final class DocumentWorkerJSHandler {
    typealias NativeONNXModelDataProvider = (String) throws -> Data

    enum Error: Swift.Error {
        case missingWorkFile
        case invalidMessage
        case unsupportedAction(String)
        case workerError(String)
        case missingData
        case invalidBundledWorkerDataPath(String)
        case missingBundledWorkerData(String)
    }

    var workFile: File?
    var shouldCacheWorkInput: Bool = false
    let observable: PublishSubject<(workId: String, result: Result<DocumentWorkerOutput, Swift.Error>)>

    private let engine: DocumentWorkerJSEngine
    private let bundle: Bundle
    private let queue: DispatchQueue
    private let queueKey: DispatchSpecificKey<String>
    private let queueLabel: String
    private var nextMessageId: Int
    private var pending: [Int: (Result<Any, Swift.Error>) -> Void]
    private var loadError: Swift.Error?
    private var cachedWorkData: Data?
    private let usesNativeONNXForStructuredDocumentText: Bool
#if MAINAPP
    private let nativeONNXBridge: DocumentWorkerNativeONNXBridge?
#endif

    init(
        bundle: Bundle = .main,
        warmUp: Bool = true,
        nativeONNXModelDataProvider: NativeONNXModelDataProvider? = nil,
        usesNativeONNXForStructuredDocumentText: Bool = false
    ) {
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
        self.usesNativeONNXForStructuredDocumentText = usesNativeONNXForStructuredDocumentText
#if MAINAPP
        nativeONNXBridge = nativeONNXModelDataProvider.map { DocumentWorkerNativeONNXBridge(modelDataProvider: $0) }
#endif

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

        case "NativeONNXRun":
#if MAINAPP
            do {
                guard let nativeONNXBridge else {
                    throw DocumentWorkerNativeONNXBridge.Error.modelDataProviderUnavailable
                }
                try respondWithData(to: engine, id: id, data: nativeONNXBridge.run(payload: data))
            } catch {
                respondWithError(to: engine, id: id, message: "\(error)")
            }
#else
            respondWithError(to: engine, id: id, message: "native ONNX is unavailable")
#endif

        default:
            respondWithError(to: engine, id: id, message: "unknown action \(action)")
        }

        func respondWithData(to engine: DocumentWorkerJSEngine, id: Int, data: Any) throws {
            let response = engine.makeObject()
            guard let dataValue = engine.makeValue(data) else {
                throw Error.invalidMessage
            }
            response.setValue(id, forProperty: "responseID")
            response.setValue(dataValue, forProperty: "data")
            try engine.postToWorker(response)
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
            let data: Data
            do {
                data = try Self.bundledWorkerData(for: path, in: bundle)
            } catch {
                respondWithError(to: engine, id: responseId, message: "\(error)")
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

    private func startWork(action: DocumentWorkerAction, workId: String) {
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
            guard supportsAction(action) else {
                deferredError = Error.unsupportedAction(action.method)
                return
            }
            let url = workFile.createUrl()
            do {
                let data: Data
                if shouldCacheWorkInput {
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
                message.setValue(action.method, forProperty: "action")

                let dataObject = engine.makeObject()
                dataObject.setValue(buffer, forProperty: "buf")
                var pages: [Int]?
                var contentType: String?
                var password: String?
                var sourceHash: String?
                var nativeONNX = false
                switch action {
                case .recognizePDF(let _password):
                    password = _password

                case .getPDFFulltext(let _pages, let _password):
                    pages = _pages
                    password = _password

                case .getStructuredDocumentText(let _contentType, let _password, let _sourceHash):
                    contentType = _contentType
                    password = _password
                    sourceHash = _sourceHash
#if MAINAPP
                    nativeONNX = usesNativeONNXForStructuredDocumentText && nativeONNXBridge != nil
#endif
                }
                if let pages {
                    dataObject.setValue(pages, forProperty: "pageIndexes")
                }
                if let contentType {
                    dataObject.setValue(contentType, forProperty: "contentType")
                }
                if let password {
                    dataObject.setValue(password, forProperty: "password")
                }
                if let sourceHash {
                    dataObject.setValue(sourceHash, forProperty: "sourceHash")
                }
                if nativeONNX {
                    dataObject.setValue(true, forProperty: "nativeONNX")
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
                        case .recognizePDF:
                            observable.on(.next((workId: workId, result: .success(.recognizerData(data: data)))))

                        case .getPDFFulltext:
                            observable.on(.next((workId: workId, result: .success(.fullText(data: data)))))

                        case .getStructuredDocumentText:
                            observable.on(.next((workId: workId, result: .success(.structuredDocumentText(data: data)))))
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

    private static func bundledWorkerData(for path: String, in bundle: Bundle) throws -> Data {
        let normalizedPath = path.replacingOccurrences(of: "\\", with: "/")
        let components = normalizedPath.split(separator: "/", omittingEmptySubsequences: false)
        let hasUnsafeComponent = components.contains { $0.isEmpty || $0 == ".." }
        guard !normalizedPath.isEmpty,
              !normalizedPath.hasPrefix("/"),
              !hasUnsafeComponent else {
            throw Error.invalidBundledWorkerDataPath(path)
        }

        let nsPath = normalizedPath as NSString
        let resourceName = nsPath.lastPathComponent
        guard !resourceName.isEmpty, resourceName != "." else {
            throw Error.invalidBundledWorkerDataPath(path)
        }
        let directory = nsPath.deletingLastPathComponent
        let subdirectory: String
        if directory.isEmpty || directory == "." {
            subdirectory = "Bundled/document_worker"
        } else {
            subdirectory = "Bundled/document_worker/\(directory)"
        }

        guard let url = bundle.url(forResource: resourceName, withExtension: nil, subdirectory: subdirectory) else {
            throw Error.missingBundledWorkerData(path)
        }
        return try Data(contentsOf: url)
    }
}

extension DocumentWorkerJSHandler: DocumentWorkerHandling {
    func supportsAction(_ action: DocumentWorkerAction) -> Bool {
        switch action {
        case .recognizePDF, .getPDFFulltext:
            return true

        case .getStructuredDocumentText:
#if MAINAPP
            return usesNativeONNXForStructuredDocumentText && nativeONNXBridge != nil
#else
            return false
#endif
        }
    }

    func performAction(_ action: DocumentWorkerAction, workId: String) {
        startWork(action: action, workId: workId)
    }
}
