//
//  WebViewHandler.swift
//  ZShare
//
//  Created by Michal Rentka on 05/12/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import WebKit

import CocoaLumberjackSwift
import RxSwift

class WebViewHandler: NSObject {
    /// Actions that can be returned by this handler.
    /// - loadedItems: Items have been translated.
    /// - selectItem: Multiple items have been found on this website and the user needs to choose one.
    /// - reportProgress: Reports progress of translation.
    /// - saveAsWeb: Translation failed. Save as webpage item.
    enum Action {
        case loadedItems([[String: Any]])
        case selectItem([(key: String, value: String)])
        case reportProgress(String)
    }

    /// Handlers for communication with JS in `webView`
    enum JSHandlers: String, CaseIterable {
        /// Handler used for HTTP requests. Expects response (HTTP response).
        case request = "requestHandler"
        /// Handler used for passing translated items.
        case item = "itemResponseHandler"
        /// Handler used for item selection. Expects response (selected item).
        case itemSelection = "itemSelectionHandler"
        /// Handler used to indicate that all translators failed to save and should be saved as web page
        case saveAsWeb = "saveAsWebHandler"
        /// Handler used to report progress of translation
        case progress = "translationProgressHandler"
        /// Handler used to log JS debug info.
        case log = "logHandler"
    }

    enum Error: Swift.Error {
        case cantFindBaseFile
        case incompatibleItem
        case javascriptCallMissingResult
        case noSuccessfulTranslators
        case webExtractionMissingJs
        case webExtractionMissingData
    }

    private let translatorsController: TranslatorsController
    private let disposeBag: DisposeBag
    let observable: PublishSubject<WebViewHandler.Action>

    private weak var webView: WKWebView?
    private var webDidLoad: ((SingleEvent<()>) -> Void)?
    private var itemSelectionMessageId: Int?
    // Cookies from original website are stored and added to requests in `sendRequest(with:)`.
    private var cookies: String?

    // MARK: - Lifecycle

    init(webView: WKWebView, translatorsController: TranslatorsController) {
        self.webView = webView
        self.disposeBag = DisposeBag()
        self.translatorsController = translatorsController
        self.observable = PublishSubject()

        super.init()

        webView.navigationDelegate = self
        JSHandlers.allCases.forEach { handler in
            webView.configuration.userContentController.add(self, name: handler.rawValue)
        }
    }

    // MARK: - Actions

    func loadWebData(from url: URL) -> Single<ExtensionStore.State.RawAttachment> {
        return self.load(url: url)
                   .flatMap({ _ -> Single<Any> in
                       guard let url = Bundle.main.url(forResource: "webview_extraction", withExtension: "js"),
                             let script = try? String(contentsOf: url) else { return Single.error(Error.webExtractionMissingJs) }
                       return self.callJavascript(script)
                   })
                   .flatMap({ data -> Single<ExtensionStore.State.RawAttachment> in
                       guard let payload = data as? [String: Any],
                             let isFile = payload["isFile"] as? Bool else {
                           return Single.error(Error.webExtractionMissingData)
                       }

                       if isFile {
                           return Single.just(.remoteFileUrl(url))
                       } else if let title = payload["title"] as? String,
                                 let html = payload["html"] as? String,
                                 let cookies = payload["cookies"] as? String,
                                 let frames = payload["frames"] as? [String] {
                           return Single.just(.web(title: title, url: url, html: html, cookies: cookies, frames: frames))
                       } else {
                           return Single.error(Error.webExtractionMissingData)
                       }
                   })
    }

    /// Runs translation server against html content with cookies. Results are then provided through observable publisher.
    /// - parameter url: Original URL of shared website.
    /// - parameter title: Title of the shared website.
    /// - parameter html: HTML content of the shared website. Equals to javascript "document.documentElement.innerHTML".
    /// - parameter cookies: Cookies string from shared website. Equals to javacsript "document.cookie".
    /// - parameter frames: HTML content of frames contained in initial HTML document.
    func translate(url: URL, title: String, html: String, cookies: String, frames: [String]) {
        guard let containerUrl = Bundle.main.url(forResource: "src/index", withExtension: "html", subdirectory: "translation"),
              let containerHtml = try? String(contentsOf: containerUrl, encoding: .utf8) else {
            self.observable.on(.error(Error.cantFindBaseFile))
            return
        }

        let encodedHtml = self.encodeForJavascript(html.data(using: .utf8))
        let jsonFramesData = try? JSONSerialization.data(withJSONObject: frames, options: .fragmentsAllowed)
        let encodedFrames = jsonFramesData.flatMap({ self.encodeForJavascript($0) }) ?? "''"
        self.cookies = cookies

        return self.load(html: containerHtml, baseUrl: containerUrl)
                   .flatMap { _ -> Single<[RawTranslator]> in
                       return self.translatorsController.translators()
                   }
                   .flatMap { translators -> Single<Any> in
                       let encodedTranslators = self.encodeJSONForJavascript(translators)
                       return self.callJavascript("translate('\(url.absoluteString)', \(encodedHtml), \(encodedFrames), \(encodedTranslators));")
                   }
                   .subscribe(onError: { [weak self] error in
                       self?.observable.on(.error(error))
                   })
                   .disposed(by: self.disposeBag)
    }

    /// Sends selected item back to `webView`.
    /// - parameter item: Selected item by the user.
    func selectItem(_ item: (String, String)) {
        guard let messageId = self.itemSelectionMessageId else { return }
        let (key, value) = item
        self.webView?.evaluateJavaScript("Zotero.Messaging.receiveResponse('\(messageId)', \(self.encodeJSONForJavascript([key: value])));",
                                        completionHandler: nil)
        self.itemSelectionMessageId = nil
    }

    /// Load the translation server.
    private func load(html: String, baseUrl: URL) -> Single<()> {
        self.webView?.loadHTMLString(html, baseURL: baseUrl)
        return self.createWebLoadedSingle()
    }

    /// Load provided url.
    private func load(url: URL) -> Single<()> {
        let request = URLRequest(url: url)
        self.webView?.load(request)
        return self.createWebLoadedSingle()
    }

    /// Create single which is fired when webview loads a resource or fails.
    private func createWebLoadedSingle() -> Single<()> {
        return Single.create { [weak self] subscriber -> Disposable in
            self?.webDidLoad = subscriber
            return Disposables.create {
                self?.webDidLoad = nil
            }
        }
    }

    // MARK: - Communication with WKWebView

    /// Sends HTTP request based on options. Sends back response with HTTP response to `webView`.
    /// - parameter options: Options for HTTP request.
    private func sendRequest(with options: [String: Any], for messageId: Int) {
        guard let urlString = options["url"] as? String,
              let url = URL(string: urlString),
              let method = options["method"] as? String else {
            let error = "Incorrect URL request from javascript".data(using: .utf8)
            let script = self.javascript(for: messageId, statusCode: -1, successCodes: [200], data: error)
            self.webView?.evaluateJavaScript(script, completionHandler: nil)
            return
        }

        let headers = (options["headers"] as? [String: String]) ?? [:]
        let body = options["body"] as? String
        let timeout = (options["timeout"] as? Double).flatMap({ $0 / 1000 }) ?? 60
        let successCodes = (options["successCodes"] as? [Int]) ?? []

        var request = URLRequest(url: url)
        request.httpMethod = method
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let cookies = self.cookies {
            request.setValue(cookies, forHTTPHeaderField: "Cookie")
        }
        request.httpBody = body?.data(using: .utf8)
        request.timeoutInterval = timeout

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 400
            guard let script = self?.javascript(for: messageId, statusCode: statusCode, successCodes: successCodes, data: data) else { return }

            DispatchQueue.main.async {
                self?.webView?.evaluateJavaScript(script, completionHandler: nil)
            }
        }
        task.resume()
    }

    private func sendError(_ error: String, for messageId: Int) {
        let payload: [String: Any] = ["error": ["message": error]]
        let script = "Zotero.Messaging.receiveResponse('\(messageId)', \(self.encodeJSONForJavascript(payload)));"
        self.webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    private func javascript(for messageId: Int, statusCode: Int, successCodes: [Int], data: Data?) -> String {
        let isSuccess = successCodes.isEmpty ? 200..<300 ~= statusCode : successCodes.contains(statusCode)
        let responseText = data.flatMap({ String(data: $0, encoding: .utf8) }) ?? ""

        var payload: [String: Any]
        if isSuccess {
            payload = ["status": statusCode, "responseText": responseText]
        } else {
            payload = ["error": ["status": statusCode, "responseText": responseText]]
        }

        return "Zotero.Messaging.receiveResponse('\(messageId)', \(self.encodeJSONForJavascript(payload)));"
    }

    // MARK: - Helpers

    /// Makes a javascript call to `webView` with `Single` response.
    /// - parameter script: JS script to be performed.
    /// - returns: `Single` with response from `webView`.
    private func callJavascript(_ script: String) -> Single<Any> {
        return Single.create { subscriber -> Disposable in
            self.webView?.evaluateJavaScript(script) { result, error in
                if let data = result {
                    subscriber(.success(data))
                } else {
                    let error = error ?? Error.javascriptCallMissingResult
                    let nsError = error as NSError

                    // TODO: - Check JS code to see if it's possible to remove this error.
                    // For some calls we get an WKWebView error "JavaScript execution returned a result of an unsupported type" even though
                    // no error really occured in the code. Because of this error the observable doesn't send any more "next" events and we don't
                    // receive the response. So we just ignore this error.
                    if nsError.domain == WKErrorDomain && nsError.code == 5 {
                        return
                    }

                    DDLogError("Javascript call ('\(script)') error: \(error)")

                    subscriber(.error(error))
                }
            }

            return Disposables.create()
        }
    }

    /// Encodes data which need to be sent to `webView`. All data that is passed to JS is Base64 encoded so that it can be sent as a simple `String`.
    private func encodeForJavascript(_ data: Data?) -> String {
        return data.flatMap({ "'" + $0.base64EncodedString(options: .endLineWithLineFeed) + "'" }) ?? "null"
    }

    /// Encodes JSON payload so that it can be sent to `webView`.
    private func encodeJSONForJavascript(_ payload: Any) -> String {
        let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
        return self.encodeForJavascript(data)
    }
}

extension WebViewHandler: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Wait for javascript to load
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            self.webDidLoad?(.success(()))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Swift.Error) {
        self.webDidLoad?(.error(error))
    }
}

/// Communication with JS in `webView`. The `webView` sends a message through one of the registered `JSHandlers`, which is received here.
/// Each message contains a `messageId` in the body, which is used to identify the message in case a response is expected.
extension WebViewHandler: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let handler = JSHandlers(rawValue: message.name) else { return }

        switch handler {
        case .request:
            guard let body = message.body as? [String: Any],
                  let messageId = body["messageId"] as? Int else { return }

            if let options = body["payload"] as? [String: Any] {
                self.sendRequest(with: options, for: messageId)
            } else {
                self.sendError("HTTP request missing payload", for: messageId)
            }
        case .itemSelection:
            guard let body = message.body as? [String: Any],
                  let messageId = body["messageId"] as? Int else { return }

            if let payload = body["payload"] as? [[String]] {
                self.itemSelectionMessageId = messageId

                var sortedDictionary: [(String, String)] = []
                for data in payload {
                    guard data.count == 2 else { continue }
                    sortedDictionary.append((data[0], data[1]))
                }

                self.observable.on(.next(.selectItem(sortedDictionary)))
            } else {
                self.sendError("Item selection missing payload", for: messageId)
            }
        case .item:
            if let info = message.body as? [[String: Any]] {
                self.observable.on(.next(.loadedItems(info)))
            } else {
                self.observable.on(.error(Error.incompatibleItem))
            }
        case .progress:
            if let progress = message.body as? String {
                if progress == "item_selection" {
                    self.observable.on(.next(.reportProgress(L10n.Shareext.Translation.itemSelection)))
                } else if progress.starts(with: "translating_with_") {
                    let name = progress[progress.index(progress.startIndex, offsetBy: 17)..<progress.endIndex]
                    self.observable.on(.next(.reportProgress(L10n.Shareext.Translation.translatingWith(name))))
                } else {
                    self.observable.on(.next(.reportProgress(progress)))
                }
            }
        case .saveAsWeb:
            self.observable.on(.error(Error.noSuccessfulTranslators))
        case .log:
            DDLogInfo("JSLOG: \(message.body)")
        }
    }
}
