//
//  DocumentWorkerWebViewHandler.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 5/5/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import WebKit

import CocoaLumberjackSwift
import RxSwift

final class DocumentWorkerWebViewHandler: WebViewHandler {
    typealias NativeONNXModelDataProvider = (String) throws -> Data

    /// Handlers for communication with JS in `webView`.
    enum JSHandlers: String, CaseIterable {
        case recognizerData = "recognizerDataHandler"
        case fullText = "fullTextHandler"
        case structuredDocumentText = "structuredDocumentTextHandler"
        case nativeONNX = "nativeONNXHandler"
        case log = "logHandler"
    }

    enum Error: Swift.Error {
        case cantFindWorkFile
        case unsupportedAction(String)
        case invalidNativeONNXBridgePayload(String)
    }

    private let disposeBag: DisposeBag
    let temporaryDirectory: File
    var workFile: File?
    var shouldCacheWorkInput: Bool = false
    private let cleanup: (() -> Void)?
    let observable: PublishSubject<(workId: String, result: Result<DocumentWorkerOutput, Swift.Error>)>
    private let usesNativeONNXForStructuredDocumentText: Bool
    private var nativeONNXBridgeResponses: [String: (Result<[String: Any], Swift.Error>) -> Void]
#if MAINAPP
    private let nativeONNXBridge: DocumentWorkerNativeONNXBridge?
#endif

    init(
        webView: WKWebView,
        temporaryDirectory: File,
        cleanup: (() -> Void)?,
        nativeONNXModelDataProvider: NativeONNXModelDataProvider? = nil,
        usesNativeONNXForStructuredDocumentText: Bool = false
    ) {
        self.temporaryDirectory = temporaryDirectory
        self.cleanup = cleanup
        self.usesNativeONNXForStructuredDocumentText = usesNativeONNXForStructuredDocumentText
        observable = PublishSubject()
        disposeBag = DisposeBag()
        nativeONNXBridgeResponses = [:]
#if MAINAPP
        nativeONNXBridge = nativeONNXModelDataProvider.map { DocumentWorkerNativeONNXBridge(modelDataProvider: $0) }
#endif

        super.init(webView: webView, javascriptHandlers: JSHandlers.allCases.map({ $0.rawValue }))

        receivedMessageHandler = { [weak self] name, body in
            self?.receiveMessage(name: name, body: body)
        }
    }

    deinit {
        cleanup?()
    }

    override func initializeWebView() -> Single<()> {
        DDLogInfo("DocumentWorkerWebViewHandler: initialize web view")
        return load(fileUrl: temporaryDirectory.copy(withName: "document_worker", ext: "html").createUrl())
    }

#if MAINAPP
    func nativeONNXBridgeEcho(payload: [String: Any]) -> Single<[String: Any]> {
        nativeONNXBridgeRequest(action: "echo", payload: ["payload": payload])
    }

    func nativeONNXBridgeRun(model: String, inputs: [[String: Any]], outputNames: [String]) -> Single<[String: Any]> {
        nativeONNXBridgeRequest(action: "run", payload: [
            "model": model,
            "inputs": inputs,
            "outputNames": outputNames
        ])
    }

    private func nativeONNXBridgeRequest(action: String, payload: [String: Any]) -> Single<[String: Any]> {
        performAfterInitialization()
            .observe(on: MainScheduler.instance)
            .flatMap { [weak self] _ -> Single<[String: Any]> in
                guard let self else { return .never() }
                return Single.create { [weak self] subscriber in
                    guard let self else { return Disposables.create() }
                    let id = UUID().uuidString
                    self.nativeONNXBridgeResponses[id] = { result in
                        switch result {
                        case .success(let data):
                            subscriber(.success(data))

                        case .failure(let error):
                            subscriber(.failure(error))
                        }
                    }

                    let javascript = """
                    window.webkit.messageHandlers.\(JSHandlers.nativeONNX.rawValue).postMessage({
                        id: \(Self.jsLiteral(id)),
                        action: \(Self.jsLiteral(action)),
                        \(Self.jsObjectEntriesLiteral(payload))
                    });
                    """

                    self.call(javascript: javascript)
                        .subscribe(onFailure: { [weak self] error in
                            self?.nativeONNXBridgeResponses.removeValue(forKey: id)
                            subscriber(.failure(error))
                        })
                        .disposed(by: self.disposeBag)

                    return Disposables.create { [weak self] in
                        self?.nativeONNXBridgeResponses.removeValue(forKey: id)
                    }
                }
            }
    }
#endif

    private func performOperation(action: DocumentWorkerAction, workId: String) {
        performAfterInitialization()
            .observe(on: MainScheduler.instance)
            .flatMap { [weak self] _ -> Single<Any> in
                guard let self else { return .never() }
                guard let workFile else { return .error(Error.cantFindWorkFile) }
                guard supportsAction(action) else { return .error(Error.unsupportedAction(action.method))}
                DDLogInfo("DocumentWorkerWebViewHandler: call \(action.method) js")

                var parameters: [String: Any] = [:]
                switch action {
                case .recognizePDF(let password):
                    parameters["password"] = password

                case .getPDFFulltext(let pages, let password):
                    parameters["pageIndexes"] = pages
                    parameters["password"] = password

                case .getStructuredDocumentText(let contentType, let password, let sourceHash):
                    parameters["contentType"] = contentType
                    parameters["password"] = password
                    parameters["sourceHash"] = sourceHash
#if MAINAPP
                    parameters["nativeONNX"] = usesNativeONNXForStructuredDocumentText && nativeONNXBridge != nil
#endif
                }

                let javascript = "performAction(\(Self.jsLiteral(action.method)), \(Self.jsLiteral(workId)), \(Self.jsLiteral(workFile.fileName)), \(Self.jsLiteral(parameters)));"
                return call(javascript: javascript)
            }
            .subscribe(onFailure: { [weak self] error in
                DDLogError("DocumentWorkerWebViewHandler: \(action.method) failed - \(error)")
                self?.observable.on(.next((workId: workId, result: .failure(error))))
            })
            .disposed(by: disposeBag)
    }

    private static func jsLiteral(_ value: Any?) -> String {
        let normalized = value ?? NSNull()
        guard JSONSerialization.isValidJSONObject([normalized]),
              let data = try? JSONSerialization.data(withJSONObject: [normalized]),
              let json = String(data: data, encoding: .utf8),
              json.hasPrefix("["),
              json.hasSuffix("]") else {
            return "null"
        }
        return String(json.dropFirst().dropLast())
    }

    private static func jsObjectEntriesLiteral(_ value: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let json = String(data: data, encoding: .utf8),
              json.hasPrefix("{"),
              json.hasSuffix("}") else {
            return ""
        }
        return String(json.dropFirst().dropLast())
    }

    /// Communication with JS in `webView`.
    private func receiveMessage(name: String, body: Any) {
        guard let handler = JSHandlers(rawValue: name) else { return }

        switch handler {
        case .recognizerData:
            guard let body = body as? [String: Any], let workId = body["workId"] as? String, let data = body["recognizerData"] as? [String: Any] else { return }
            observable.on(.next((workId: workId, result: .success(.recognizerData(data: data)))))

        case .fullText:
            guard let body = body as? [String: Any], let workId = body["workId"] as? String, let data = body["fullText"] as? [String: Any] else { return }
            observable.on(.next((workId: workId, result: .success(.fullText(data: data)))))

        case .structuredDocumentText:
            guard let body = body as? [String: Any], let workId = body["workId"] as? String, let data = body["structuredDocumentText"] as? [String: Any] else { return }
            observable.on(.next((workId: workId, result: .success(.structuredDocumentText(data: data)))))

        case .nativeONNX:
#if MAINAPP
            processNativeONNXBridgeMessage(body)
#else
            break
#endif

        case .log:
            DDLogInfo("DocumentWorkerWebViewHandler: JSLOG - \(body)")
        }
    }

#if MAINAPP
    private func processNativeONNXBridgeMessage(_ body: Any) {
        guard let body = body as? [String: Any], let id = body["id"] as? String, let action = body["action"] as? String else { return }

        switch action {
        case "echo":
            let result: [String: Any] = [
                "payload": body["payload"] ?? NSNull(),
                "runtime": "native"
            ]
            completeNativeONNXBridgeRequest(id: id, result: .success(result))

        case "run":
            do {
                guard let nativeONNXBridge else {
                    throw DocumentWorkerNativeONNXBridge.Error.modelDataProviderUnavailable
                }
                let result = try nativeONNXBridge.run(payload: body)
                completeNativeONNXBridgeRequest(id: id, result: .success(result))
            } catch {
                completeNativeONNXBridgeRequest(id: id, result: .failure(error))
            }

        default:
            let error = Error.unsupportedAction("nativeONNX.\(action)")
            completeNativeONNXBridgeRequest(id: id, result: .failure(error))
        }
    }

    private func completeNativeONNXBridgeRequest(id: String, result: Result<[String: Any], Swift.Error>) {
        if let completion = nativeONNXBridgeResponses.removeValue(forKey: id) {
            completion(result)
            return
        }

        switch result {
        case .success(let result):
            sendNativeONNXBridgeResponse(id: id, result: result)

        case .failure(let error):
            sendNativeONNXBridgeError(id: id, error: "\(error)")
        }
    }

    private func sendNativeONNXBridgeResponse(id: String, result: [String: Any]) {
        let response: [String: Any] = ["result": result]
        let javascript = """
        window.__zoteroNativeONNXBridgeReceiveResponse && window.__zoteroNativeONNXBridgeReceiveResponse(\(Self.jsLiteral(id)), \(Self.jsLiteral(response)));
        """
        call(javascript: javascript)
            .subscribe()
            .disposed(by: disposeBag)
    }

    private func sendNativeONNXBridgeError(id: String, error: String) {
        let response: [String: Any] = ["error": error]
        let javascript = """
        window.__zoteroNativeONNXBridgeReceiveResponse && window.__zoteroNativeONNXBridgeReceiveResponse(\(Self.jsLiteral(id)), \(Self.jsLiteral(response)));
        """
        call(javascript: javascript)
            .subscribe()
            .disposed(by: disposeBag)
    }
#endif
}

extension DocumentWorkerWebViewHandler: DocumentWorkerHandling {
    func supportsAction(_ action: DocumentWorkerAction) -> Bool {
        switch action {
        case .recognizePDF, .getPDFFulltext, .getStructuredDocumentText:
            return true
        }
    }

    func performAction(_ action: DocumentWorkerAction, workId: String) {
        performOperation(action: action, workId: workId)
    }
}
