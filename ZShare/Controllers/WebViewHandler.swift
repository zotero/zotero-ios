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

final class WebViewHandler: NSObject {
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
        case cantFindFile
        case incompatibleItem
        case javascriptCallMissingResult
        case noSuccessfulTranslators
        case webExtractionMissingJs
        case webExtractionMissingData
        case webViewMissing
    }

    private let translatorsController: TranslatorsAndStylesController
    private let disposeBag: DisposeBag
    let observable: PublishSubject<WebViewHandler.Action>

    private weak var webView: WKWebView?
    private var webDidLoad: ((SingleEvent<()>) -> Void)?
    private var itemSelectionMessageId: Int?
    // Cookies from original website are stored and added to requests in `sendRequest(with:)`.
    private var cookies: String?

    // MARK: - Lifecycle

    init(webView: WKWebView, translatorsController: TranslatorsAndStylesController) {
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
        guard let webView = self.webView else { return Single.error(Error.webViewMissing) }

        DDLogInfo("WebViewHandler: load web data")

        return self.load(url: url)
                   .flatMap({ _ -> Single<Any> in
                       guard let url = Bundle.main.url(forResource: "webview_extraction", withExtension: "js"),
                             let script = try? String(contentsOf: url) else {
                           DDLogError("WebViewHandler: can't load extraction javascript")
                           return Single.error(Error.webExtractionMissingJs)
                       }
                       DDLogInfo("WebViewHandler: call data extraction js")
                       return webView.call(javascript: script)
                   })
                   .flatMap({ data -> Single<ExtensionStore.State.RawAttachment> in
                       guard let payload = data as? [String: Any],
                             let isFile = payload["isFile"] as? Bool else {
                           DDLogError("WebViewHandler: extracted data missing response")
                           DDLogError("\(data as? [String: Any])")
                           return Single.error(Error.webExtractionMissingData)
                       }

                       if isFile, let contentType = payload["contentType"] as? String {
                           DDLogInfo("WebViewHandler: extracted file")
                           return Single.just(.remoteFileUrl(url: url, contentType: contentType))
                       } else if let title = payload["title"] as? String,
                                 let html = payload["html"] as? String,
                                 let cookies = payload["cookies"] as? String,
                                 let frames = payload["frames"] as? [String] {
                           DDLogInfo("WebViewHandler: extracted html")
                           return Single.just(.web(title: title, url: url, html: html, cookies: cookies, frames: frames))
                       } else {
                           DDLogError("WebViewHandler: extracted data incompatible")
                           DDLogError("\(payload)")
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
        guard let webView = self.webView else {
            DDLogError("WebViewHandler: web view is nil")
            self.observable.on(.error(Error.webViewMissing))
            return
        }

        DDLogInfo("WebViewHandler: translate")

        self.cookies = cookies

        return self.loadIndex()
                   .flatMap { _ -> Single<(String, String)> in
                       return self.loadBundledFiles()
                   }
                   .flatMap { encodedSchema, encodedDateFormats -> Single<Any> in
                       return webView.call(javascript: "initSchemaAndDateFormats(\(encodedSchema), \(encodedDateFormats));")
                   }
                   .flatMap { _ -> Single<[RawTranslator]> in
                       DDLogInfo("WebViewHandler: load translators")
                       return self.translatorsController.translators(matching: url.absoluteString)
                   }
                   .flatMap { translators -> Single<Any> in
                       DDLogInfo("WebViewHandler: encode translators")
                       let encodedTranslators = WKWebView.encodeAsJSONForJavascript(translators)
                       return webView.call(javascript: "initTranslators(\(encodedTranslators));")
                   }
                   .flatMap({ _ -> Single<Any> in
                       DDLogInfo("WebViewHandler: call translate js")
                       let encodedHtml = WKWebView.encodeForJavascript(html.data(using: .utf8))
                       let jsonFramesData = try? JSONSerialization.data(withJSONObject: frames, options: .fragmentsAllowed)
                       let encodedFrames = jsonFramesData.flatMap({ WKWebView.encodeForJavascript($0) }) ?? "''"
                       return webView.call(javascript: "translate('\(url.absoluteString)', \(encodedHtml), \(encodedFrames));")
                   })
                   .subscribe(onFailure: { [weak self] error in
                       DDLogError("WebViewHandler: translation failed - \(error)")
                       self?.observable.on(.error(error))
                   })
                   .disposed(by: self.disposeBag)
    }

    private func loadBundledFiles() -> Single<(String, String)> {
        return Single.create { subscriber in
            guard let schemaUrl = Bundle.main.url(forResource: "schema", withExtension: "json", subdirectory: "Bundled"),
                  let schemaData = try? Data(contentsOf: schemaUrl) else {
                DDLogError("WebViewHandler: can't load schema json")
                subscriber(.failure(Error.cantFindFile))
                return Disposables.create()
            }

            guard let dateFormatsUrl = Bundle.main.url(forResource: "dateFormats", withExtension: "json", subdirectory: "translation/translate/modules/utilities/resource"),
                  let dateFormatData = try? Data(contentsOf: dateFormatsUrl) else {
                DDLogError("WebViewHandler: can't load dateFormats json")
                subscriber(.failure(Error.cantFindFile))
                return Disposables.create()
            }

            let encodedSchema = WKWebView.encodeForJavascript(schemaData)
            let encodedFormats = WKWebView.encodeForJavascript(dateFormatData)

            DDLogInfo("WebViewHandler: loaded bundled files")

            subscriber(.success((encodedSchema, encodedFormats)))

            return Disposables.create()
        }
    }

    /// Sends selected item back to `webView`.
    /// - parameter item: Selected item by the user.
    func selectItem(_ item: (String, String)) {
        guard let messageId = self.itemSelectionMessageId else { return }
        let (key, value) = item
        self.webView?.evaluateJavaScript("Zotero.Messaging.receiveResponse('\(messageId)', \(WKWebView.encodeAsJSONForJavascript([key: value])));", completionHandler: nil)
        self.itemSelectionMessageId = nil
    }

    private func loadIndex() -> Single<()> {
        guard let indexUrl = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "translation") else {
            return Single.error(Error.cantFindFile)
        }
        self.webView?.loadFileURL(indexUrl, allowingReadAccessTo: indexUrl.deletingLastPathComponent())
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
            DDLogInfo("Incorrect URL request from javascript")
            DDLogInfo("\(options)")

            let error = "Incorrect URL request from javascript".data(using: .utf8)
                  let script = self.javascript(for: messageId, statusCode: -1, successCodes: [200], data: error, headers: [:])

            inMainThread { [weak self] in
                self?.webView?.evaluateJavaScript(script, completionHandler: nil)
            }
            return
        }

        guard !urlString.contains("repo/code/undefined") else {
            DDLogError("WebViewHandler: Undefined call, translator missing.")

            // Received undefined translator repo call, which happens only when translation doesn't have proper translator available and just gets stuck, so we just force this error here.
            self.observable.on(.error(Error.noSuccessfulTranslators))

            return
        }

        let headers = (options["headers"] as? [String: String]) ?? [:]
        let body = options["body"] as? String
        let timeout = (options["timeout"] as? Double).flatMap({ $0 / 1000 }) ?? 60
        let successCodes = (options["successCodes"] as? [Int]) ?? []

        DDLogInfo("WebViewHandler: send request to \(urlString)")

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
            guard let response = response as? HTTPURLResponse,
                  let script = self?.javascript(for: messageId, statusCode: response.statusCode, successCodes: successCodes, data: data, headers: response.allHeaderFields) else { return }

            DispatchQueue.main.async {
                self?.webView?.evaluateJavaScript(script, completionHandler: nil)
            }
        }
        task.resume()
    }

    private func sendError(_ error: String, for messageId: Int) {
        let payload: [String: Any] = ["error": ["message": error]]
        let script = "Zotero.Messaging.receiveResponse('\(messageId)', \(WKWebView.encodeAsJSONForJavascript(payload)));"
        self.webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    private func javascript(for messageId: Int, statusCode: Int, successCodes: [Int], data: Data?, headers: [AnyHashable: Any]) -> String {
        let isSuccess = successCodes.isEmpty ? 200..<300 ~= statusCode : successCodes.contains(statusCode)
        let responseText = data.flatMap({ String(data: $0, encoding: .utf8) }) ?? ""

        var payload: [String: Any]
        if isSuccess {
            payload = ["status": statusCode, "responseText": responseText, "headers": headers]
        } else {
            payload = ["error": ["status": statusCode, "responseText": responseText]]
        }

        return "Zotero.Messaging.receiveResponse('\(messageId)', \(WKWebView.encodeAsJSONForJavascript(payload)));"
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
        DDLogError("WebViewHandler: did fail - \(error)")
        self.webDidLoad?(.failure(error))
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
                  let messageId = body["messageId"] as? Int else {
                DDLogError("WebViewHandler: request missing body - \(message.body)")
                return
            }

            if let options = body["payload"] as? [String: Any] {
                self.sendRequest(with: options, for: messageId)
            } else {
                DDLogError("WebViewHandler: request missing payload - \(body)")
                self.sendError("HTTP request missing payload", for: messageId)
            }
        case .itemSelection:
            guard let body = message.body as? [String: Any],
                  let messageId = body["messageId"] as? Int else {
                DDLogError("WebViewHandler: item selection missing body - \(message.body)")
                return
            }

            if let payload = body["payload"] as? [[String]] {
                self.itemSelectionMessageId = messageId

                var sortedDictionary: [(String, String)] = []
                for data in payload {
                    guard data.count == 2 else { continue }
                    sortedDictionary.append((data[0], data[1]))
                }

                self.observable.on(.next(.selectItem(sortedDictionary)))
            } else {
                DDLogError("WebViewHandler: item selection missing payload - \(body)")
                self.sendError("Item selection missing payload", for: messageId)
            }
        case .item:
            if let info = message.body as? [[String: Any]] {
                self.observable.on(.next(.loadedItems(info)))
            } else {
                DDLogError("WebViewHandler: got incompatible body - \(message.body)")
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
