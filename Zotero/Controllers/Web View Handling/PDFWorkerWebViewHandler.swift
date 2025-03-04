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
import RxCocoa
import RxSwift

final class PDFWorkerWebViewHandler: WebViewHandler {
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
        case cantFindFile
    }

    enum PDFWorkerData {
        case recognizerData(data: [String: Any])
        case fullText(data: [String: Any])
    }

    private let disposeBag: DisposeBag
    let observable: PublishSubject<Result<PDFWorkerData, Swift.Error>>

    init(webView: WKWebView) {
        observable = PublishSubject()
        disposeBag = DisposeBag()

        super.init(webView: webView, javascriptHandlers: JSHandlers.allCases.map({ $0.rawValue }))

        receivedMessageHandler = { [weak self] name, body in
            self?.receiveMessage(name: name, body: body)
        }
    }

    override func initializeWebView() -> Single<()> {
        DDLogInfo("PDFWorkerWebViewHandler: initialize web view")
        return loadIndex()
            .flatMap { _ in
                Single.just(Void())
            }

        func loadIndex() -> Single<()> {
            guard let indexUrl = Bundle.main.url(forResource: "worker", withExtension: "html") else {
                return .error(Error.cantFindFile)
            }
            return load(fileUrl: indexUrl)
        }
    }

    private func performPDFWorkerOperation(file: FileData, operationName: String, jsFunction: String) {
        performAfterInitialization()
            .flatMap { [weak self] _ -> Single<Any> in
                guard let self else { return .never() }
                let filePath = file.createUrl().path
                DDLogInfo("PDFWorkerWebViewHandler: call \(operationName) js")
                return call(javascript: "\(jsFunction)('\(filePath)');")
            }
            .subscribe(onFailure: { [weak self] error in
                DDLogError("PDFWorkerWebViewHandler: \(operationName) failed - \(error)")
                self?.observable.on(.next(.failure(error)))
            })
            .disposed(by: disposeBag)
    }

    func recognize(file: FileData) {
        performPDFWorkerOperation(file: file, operationName: "recognize", jsFunction: "recognize")
    }

    func getFullText(file: FileData) {
        performPDFWorkerOperation(file: file, operationName: "getFullText", jsFunction: "getFullText")
    }

    /// Communication with JS in `webView`. The `webView` sends a message through one of the registered `JSHandlers`, which is received here.
    /// Each message contains a `messageId` in the body, which is used to identify the message in case a response is expected.
    private func receiveMessage(name: String, body: Any) {
        guard let handler = JSHandlers(rawValue: name) else { return }

        switch handler {
        case .recognizerData:
            guard let data = (body as? [String: Any])?["recognizerData"] as? [String: Any] else { return }
            observable.on(.next(.success(.recognizerData(data: data))))

        case .fullText:
            guard let data = (body as? [String: Any])?["fullText"] as? [String: Any] else { return }
            observable.on(.next(.success(.recognizerData(data: data))))

        case .log:
            DDLogInfo("PDFWorkerWebViewHandler: JSLOG - \(body)")
        }
    }
}
