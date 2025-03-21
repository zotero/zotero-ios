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

final class PDFWorkerWebViewHandler {
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

    private enum InitializationState {
        case initialized
        case inProgress
        case failed(Swift.Error)
    }

    let webViewHandler: WebViewHandler
    private let disposeBag: DisposeBag
    let observable: PublishSubject<Result<PDFWorkerData, Swift.Error>>

    private var initializationState: BehaviorRelay<InitializationState>

    init(webView: WKWebView) {
        webViewHandler = WebViewHandler(webView: webView, javascriptHandlers: JSHandlers.allCases.map({ $0.rawValue }))
        observable = PublishSubject()
        disposeBag = DisposeBag()
        initializationState = BehaviorRelay(value: .inProgress)

        webViewHandler.receivedMessageHandler = { [weak self] name, body in
            self?.receiveMessage(name: name, body: body)
        }

        initialize()
            .subscribe(on: MainScheduler.instance)
            .observe(on: MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] _ in
                DDLogInfo("PDFWorkerWebViewHandler: initialization succeeded")
                self?.initializationState.accept(.initialized)
            }, onFailure: { [weak self] error in
                DDLogInfo("PDFWorkerWebViewHandler: initialization failed - \(error)")
                self?.initializationState.accept(.failed(error))
            })
            .disposed(by: disposeBag)

        func initialize() -> Single<()> {
            DDLogInfo("PDFWorkerWebViewHandler: initialize web view")
            return loadIndex()

            func loadIndex() -> Single<()> {
                guard let indexUrl = Bundle.main.url(forResource: "worker", withExtension: "html") else {
                    return .error(Error.cantFindFile)
                }
                return webViewHandler.load(fileUrl: indexUrl)
            }
        }
    }

    private func performAfterInitialization() -> Single<()> {
        return initializationState.filter { state in
            switch state {
            case .inProgress:
                return false

            case .initialized, .failed:
                return true
            }
        }
        .first()
        .flatMap { state -> Single<()> in
            switch state {
            case .failed(let error):
                return .error(error)

            case .initialized:
                return .just(())

            case .inProgress, .none:
                // Should never happen.
                return .never()
            }
        }
    }

    private func performPDFWorkerOperation(file: FileData, operationName: String, jsFunction: String) {
        let filePath = file.createUrl().path
        performAfterInitialization().flatMap({
            DDLogInfo("PDFWorkerWebViewHandler: call \(operationName) js")
            return self.webViewHandler.call(javascript: "\(jsFunction)('\(filePath)');")
        })
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
