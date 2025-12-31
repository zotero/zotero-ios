//
//  PDFWorkerJSHandler.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 30/12/25.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import CocoaLumberjackSwift
import RxSwift

final class PDFWorkerJSHandler: PDFWorkerHandling {
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
    let observable: PublishSubject<(workId: String, result: Result<PDFWorkerData, Swift.Error>)>

    private let engine: PDFWorkerJSEngine
    private let queue: DispatchQueue
    private let queueKey: DispatchSpecificKey<String>
    private let queueLabel: String
    private var nextMessageId: Int
    private var pending: [Int: (Result<Any, Swift.Error>) -> Void]
    private var loadError: Swift.Error?
    private var cachedWorkData: Data?

    init(bundle: Bundle = .main, warmUp: Bool = true) {
        queueLabel = "org.zotero.PDFWorkerJSHandler.queue"
        queue = DispatchQueue(label: queueLabel)
        queueKey = DispatchSpecificKey<String>()
        queue.setSpecific(key: queueKey, value: queueLabel)
        engine = PDFWorkerJSEngine(bundle: bundle, queue: queue)
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
            DDLogInfo("PDFWorkerJSHandler: JSLOG - \(message)")
        }
        engine.onException = { message in
            DDLogError("PDFWorkerJSHandler: JSEXCEPTION - \(message)")
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
                DDLogError("PDFWorkerJSHandler: failed to load worker scripts - \(error)")
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
                DDLogError("PDFWorkerJSHandler: response \(responseId) missing data")
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
        case "FetchBuiltInCMap":
            guard let name = data as? String else {
                respondWithError(to: engine, id: id, message: "missing cmap name")
                return
            }
            respondWithBuiltInCMap(to: engine, name: name, responseId: id)

        case "FetchStandardFontData":
            guard let filename = data as? String else {
                respondWithError(to: engine, id: id, message: "missing font filename")
                return
            }
            respondWithStandardFontData(to: engine, filename: filename, responseId: id)

        default:
            respondWithError(to: engine, id: id, message: "unknown action \(action)")
        }

        func respondWithError(to engine: PDFWorkerJSEngine, id: Int, message: String) {
            let response = engine.makeObject()
            let error = engine.makeObject()
            error.setValue(message, forProperty: "name")
            response.setValue(id, forProperty: "responseID")
            response.setValue(error, forProperty: "error")
            do {
                try engine.postToWorker(response)
            } catch {
                DDLogError("PDFWorkerJSHandler: failed to respond with error to JS engine - \(error)")
            }
        }

        func respondWithBuiltInCMap(to engine: PDFWorkerJSEngine, name: String, responseId: Int) {
            let path = "Bundled/pdf_worker/cmaps"
            guard let url = Bundle.main.url(forResource: name, withExtension: "bcmap", subdirectory: path) else {
                respondWithError(to: engine, id: responseId, message: "missing cmap \(name)")
                return
            }
            guard let data = try? Data(contentsOf: url) else {
                respondWithError(to: engine, id: responseId, message: "failed to read cmap \(name)")
                return
            }
            guard let cMapData = engine.makeUint8Array(from: data) else {
                respondWithError(to: engine, id: responseId, message: "failed to create cmap data")
                return
            }
            let response = engine.makeObject()
            let payload = engine.makeObject()
            payload.setValue(true, forProperty: "isCompressed")
            payload.setValue(cMapData, forProperty: "cMapData")
            response.setValue(responseId, forProperty: "responseID")
            response.setValue(payload, forProperty: "data")
            do {
                try engine.postToWorker(response)
            } catch {
                DDLogError("PDFWorkerJSHandler: failed to respond to cmap request - \(error)")
            }
        }

        func respondWithStandardFontData(to engine: PDFWorkerJSEngine, filename: String, responseId: Int) {
            let path = "Bundled/pdf_worker/standard_fonts"
            guard let url = Bundle.main.url(forResource: filename, withExtension: nil, subdirectory: path) else {
                respondWithError(to: engine, id: responseId, message: "missing font \(filename)")
                return
            }
            guard let data = try? Data(contentsOf: url) else {
                respondWithError(to: engine, id: responseId, message: "failed to read font \(filename)")
                return
            }
            guard let fontData = engine.makeUint8Array(from: data) else {
                respondWithError(to: engine, id: responseId, message: "failed to create font data")
                return
            }
            let response = engine.makeObject()
            response.setValue(responseId, forProperty: "responseID")
            response.setValue(fontData, forProperty: "data")
            do {
                try engine.postToWorker(response)
            } catch {
                DDLogError("PDFWorkerJSHandler: failed to respond to font request - \(error)")
            }
        }
    }

    func recognize(workId: String) {
        startWork(action: "getRecognizerData", pages: nil, workId: workId)
    }

    func getFullText(pages: [Int]?, workId: String) {
        startWork(action: "getFulltext", pages: pages, workId: workId)
    }

    private func startWork(action: String, pages: [Int]?, workId: String) {
        queue.async { [weak self] in
            guard let self else { return }
            var deferredError: Swift.Error?
            defer {
                if let error = deferredError {
                    DDLogError("PDFWorkerJSHandler: failed to start work - \(error)")
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
                let data = try loadWorkData(from: url)
                guard let buffer = engine.makeArrayBuffer(from: data) else {
                    throw Error.invalidMessage
                }

                let message = engine.makeObject()
                message.setValue(nextMessageId, forProperty: "id")
                message.setValue(action, forProperty: "action")

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
                        if action == "getRecognizerData" {
                            observable.on(.next((workId: workId, result: .success(.recognizerData(data: data)))))
                        } else {
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

        func loadWorkData(from url: URL) throws -> Data {
            if shouldCacheWorkData, let cachedWorkData {
                return cachedWorkData
            }
            let data: Data
            if shouldCacheWorkData {
                data = try Data(contentsOf: url, options: [.mappedIfSafe])
                cachedWorkData = data
            } else {
                data = try Data(contentsOf: url)
                cachedWorkData = nil
            }
            return data
        }
    }
}
