//
//  PDFWorkerWebViewHandler.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 24/1/25.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import WebKit

import CocoaLumberjackSwift
import RxSwift

final class PDFWorkerWebViewHandler: WebViewHandler, PDFWorkerHandling {
    /// Handlers for communication with JS in `webView`
    enum JSHandlers: String, CaseIterable {
        /// Handler used for reporting recognizer data.
        case recognizerData = "recognizerDataHandler"
        /// Handler used for reporting full text.
        case fullText = "fullTextHandler"
        /// Handler used to log JS debug info.
        case log = "logHandler"
    }

    enum Error: Swift.Error {
        case cantFindWorkFile
    }

    private let disposeBag: DisposeBag
    let temporaryDirectory: File
    var workFile: File?
    var shouldCacheWorkData: Bool = false
    private let cleanup: (() -> Void)?
    let observable: PublishSubject<(workId: String, result: Result<PDFWorkerData, Swift.Error>)>

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
        DDLogInfo("PDFWorkerWebViewHandler: initialize web view")
        return load(fileUrl: temporaryDirectory.copy(withName: "worker", ext: "html").createUrl())
    }

    private func performPDFWorkerOperation(operationName: String, jsFunction: String, additionalParams: [String] = [], workId: String) {
        performAfterInitialization()
            .observe(on: MainScheduler.instance)
            .flatMap { [weak self] _ -> Single<Any> in
                guard let self else { return .never() }
                guard let workFile else { return .error(Error.cantFindWorkFile) }
                DDLogInfo("PDFWorkerWebViewHandler: call \(operationName) js")
                var javascript = "\(jsFunction)('\(workId)', '\(escapeJavaScriptString(workFile.fileName))'"
                if !additionalParams.isEmpty {
                    javascript += ", " + additionalParams.joined(separator: ", ")
                }
                javascript += ");"
                return call(javascript: javascript)
            }
            .subscribe(onFailure: { [weak self] error in
                DDLogError("PDFWorkerWebViewHandler: \(operationName) failed - \(error)")
                self?.observable.on(.next((workId: workId, result: .failure(error))))
            })
            .disposed(by: disposeBag)

        func escapeJavaScriptString(_ string: String) -> String {
            return string
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
        }
    }

    func recognize(workId: String) {
        performPDFWorkerOperation(operationName: "recognize", jsFunction: "recognize", workId: workId)
    }

    func getFullText(pages: [Int]?, workId: String) {
        performPDFWorkerOperation(
            operationName: "getFullText",
            jsFunction: "getFullText",
            additionalParams: pages.flatMap({ ["[\($0.map({ "\($0)" }).joined(separator: ","))]"] }) ?? [],
            workId: workId
        )
    }

    /// Communication with JS in `webView`. The `webView` sends a message through one of the registered `JSHandlers`, which is received here.
    /// Each message contains a `messageId` in the body, which is used to identify the message in case a response is expected.
    private func receiveMessage(name: String, body: Any) {
        guard let handler = JSHandlers(rawValue: name) else { return }

        switch handler {
        case .recognizerData:
            guard let body = body as? [String: Any], let workId = body["workId"] as? String, let data = body["recognizerData"] as? [String: Any] else { return }
            observable.on(.next((workId: workId, result: .success(.recognizerData(data: data)))))

        case .fullText:
            guard let body = body as? [String: Any], let workId = body["workId"] as? String, let data = body["fullText"] as? [String: Any] else { return }
            observable.on(.next((workId: workId, result: .success(.fullText(data: data)))))

        case .log:
            DDLogInfo("PDFWorkerWebViewHandler: JSLOG - \(body)")
        }
    }
}
