//
//  CitationWebViewHandler.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 15/3/25.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import WebKit

import CocoaLumberjackSwift
import RxCocoa
import RxSwift

final class CitationWebViewHandler: WebViewHandler {
    /// Handlers for communication with JS in `webView`
    enum JSHandlers: String, CaseIterable {
        case citation = "citationHandler"
        case bibliography = "bibliographyHandler"
        case csl = "cslHandler"
        /// Handler used to log JS debug info.
        case log = "logHandler"
    }

    enum Error: Swift.Error {
        case deinitialized
        case cantFindFile
        case missingResponse
    }

    init(webView: WKWebView) {
        super.init(webView: webView, javascriptHandlers: JSHandlers.allCases.map({ $0.rawValue }))

        receivedMessageHandler = { [weak self] name, body in
            self?.receiveMessage(name: name, body: body)
        }
    }

    private var responseHandlers: [String: (SingleEvent<String>) -> Void] = [:]

    override func initializeWebView() -> Single<()> {
        DDLogInfo("CitationWebViewHandler: initialize web view")
        return loadIndex()

        func loadIndex() -> Single<()> {
            guard let indexUrl = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "citation") else {
                return .error(Error.cantFindFile)
            }
            return load(fileUrl: indexUrl)
        }
    }

    /// Performs javascript script, returns `Single` with registered response handler.
    private func perform(javascript: String) -> Single<String> {
        performAfterInitialization()
            .flatMap { [weak self] _ -> Single<String> in
                guard let self else { return .error(Error.deinitialized) }
                return .create { [weak self] subscriber -> Disposable in
                    guard let self else {
                        subscriber(.failure(Error.deinitialized))
                        return Disposables.create()
                    }
                    let id = UUID().uuidString
                    let javascriptWithId = javascript.replacingOccurrences(of: "msgid", with: id)
                    responseHandlers[id] = subscriber
                    let disposable = call(javascript: javascriptWithId)
                        .subscribe(on: MainScheduler.instance)
                        .observe(on: MainScheduler.instance)
                        .subscribe(onFailure: { [weak self] error in
                            guard let self else { return }
                            DDLogError("CitationWebViewHandler: javascript call failed - \(error)")
                            responseHandlers[id]?(.failure(error))
                        })

                    return Disposables.create { [weak self] in
                        self?.responseHandlers[id] = nil
                        disposable.dispose()
                    }
                }
            }
    }

    func getItemsCSL(from jsons: String, schema: String, dateFormats: String) -> Single<String> {
        DDLogInfo("CitationWebViewHandler: call get items CSL js")
        return perform(javascript: "convertItemsToCSL(\(jsons), \(schema), \(dateFormats), 'msgid');")
    }

    /// Calls javascript in webView and waits for response.
    /// - returns: Single with citation response or error.
    func getCitation(itemsCSL: String, itemsData: String, styleXML: String, localeId: String, localeXML: String, format: String, showInWebView: Bool) -> Single<String> {
        return perform(javascript: "getCit(\(itemsCSL), \(itemsData), \(styleXML), '\(localeId)', \(localeXML), '\(format)', \(showInWebView), 'msgid');")
    }

    /// Calls javascript in webView and waits for response.
    /// - returns: Single with bibliography response or error.
    func getBibliography(itemsCSL: String, styleXML: String, localeId: String, localeXML: String, format: String) -> Single<String> {
        return perform(javascript: "getBib(\(itemsCSL), \(styleXML), '\(localeId)', \(localeXML), '\(format)', 'msgid');")
    }

    /// Communication with JS in `webView`. The `webView` sends a message through one of the registered `JSHandlers`, which is received here.
    /// Each message contains a `messageId` in the body, which is used to identify the message in case a response is expected.
    private func receiveMessage(name: String, body: Any) {
        guard let handler = JSHandlers(rawValue: name) else { return }

        if handler == .log {
            DDLogInfo("CitationWebViewHandler: JSLOG - \(body)")
            return
        }

        guard let body = body as? [String: Any], let id = body["id"] as? String, let jsResult = body["result"] else {
            DDLogError("CitationWebViewHandler: unknown message body - \(body)")
            return
        }

        let result: SingleEvent<String>

        switch handler {
        case .citation, .bibliography:
            if let jsResult = jsResult as? String {
                result = .success(jsResult)
            } else {
                DDLogError("CitationWebViewHandler: Citation/Bibliography got unknown response - \(jsResult)")
                result = .failure(Error.missingResponse)
            }

        case .csl:
            if let csl = jsResult as? [[String: Any]] {
                result = .success(WebViewEncoder.encodeAsJSONForJavascript(csl))
            } else {
                DDLogError("CitationWebViewHandler: CSL got unknown response - \(jsResult)")
                result = .failure(Error.missingResponse)
            }

        case .log:
            return
        }

        if let responseHandler = responseHandlers[id] {
            responseHandler(result)
        } else {
            DDLogError("CitationWebViewHandler: response handler for \(name) with id \(id) doesn't exist anymore")
        }
    }
}
