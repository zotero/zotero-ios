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
    /// Handlers for communication with JS in `webView`.
    enum JSHandlers: String, CaseIterable {
        case recognizerData = "recognizerDataHandler"
        case fullText = "fullTextHandler"
        case structuredDocumentText = "structuredDocumentTextHandler"
        case log = "logHandler"
    }

    enum Error: Swift.Error {
        case cantFindWorkFile
        case unsupportedAction(String)
    }

    private let disposeBag: DisposeBag
    let temporaryDirectory: File
    var workFile: File?
    var shouldCacheWorkInput: Bool = false
    private let cleanup: (() -> Void)?
    let observable: PublishSubject<(workId: String, result: Result<DocumentWorkerOutput, Swift.Error>)>

    init(webView: WKWebView, temporaryDirectory: File, cleanup: (() -> Void)?) {
        self.temporaryDirectory = temporaryDirectory
        self.cleanup = cleanup
        observable = PublishSubject()
        disposeBag = DisposeBag()

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

                case .getStructuredDocumentText(let contentType, let password):
                    parameters["contentType"] = contentType
                    parameters["password"] = password
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

        case .log:
            DDLogInfo("DocumentWorkerWebViewHandler: JSLOG - \(body)")
        }
    }
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
