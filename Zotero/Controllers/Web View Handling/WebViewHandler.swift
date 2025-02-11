//
//  WebViewHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 16.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import WebKit

import CocoaLumberjackSwift
import RxSwift

final class WebViewHandler: NSObject {
    enum Error: Swift.Error {
        case webViewMissing
        case urlMissingTranslators
    }

    private let session: URLSession

    private(set) weak var webView: WKWebView?
    private var webDidLoad: ((SingleEvent<()>) -> Void)?
    var receivedMessageHandler: ((String, Any) -> Void)?
    // Cookies, User-Agent and Referrer from original website are stored and added to requests in `sendRequest(with:)`.
    private(set) var cookies: String?
    private(set) var userAgent: String?
    private(set) var referer: String?

    // MARK: - Lifecycle

    init(webView: WKWebView, javascriptHandlers: [String]?) {
        let storage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: AppGroup.identifier)
        storage.cookieAcceptPolicy = .always

        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = storage
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always

        session = URLSession(configuration: configuration)
        self.webView = webView

        super.init()

        webView.navigationDelegate = self
        let userAgent = webView.value(forKey: "userAgent") ?? ""
        webView.customUserAgent = "\(userAgent) Zotero_iOS/\(DeviceInfoProvider.versionString ?? "")-\(DeviceInfoProvider.buildString ?? "")"

        javascriptHandlers?.forEach { handler in
            webView.configuration.userContentController.add(self, name: handler)
        }
    }

    // MARK: - Actions

    func set(cookies: String?, userAgent: String?, referrer: String?) {
        self.cookies = cookies
        self.userAgent = userAgent
        self.referer = referrer
    }

    func load(fileUrl: URL) -> Single<()> {
        guard let webView else {
            DDLogError("WebViewHandler: web view is nil")
            return .error(Error.webViewMissing)
        }
        webView.loadFileURL(fileUrl, allowingReadAccessTo: fileUrl.deletingLastPathComponent())
        return createWebLoadedSingle()
    }

    func load(webUrl: URL) -> Single<()> {
        guard let webView else {
            DDLogError("WebViewHandler: web view is nil")
            return .error(Error.webViewMissing)
        }
        let request = URLRequest(url: webUrl)
        // Share extension started crashing when `load()` was called immediately, a little delay fixed the crash (##616)
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            webView.load(request)
        }
        return createWebLoadedSingle()
    }

    func call(javascript: String) -> Single<Any> {
        guard let webView else {
            DDLogError("WebViewHandler: web view is nil")
            return .error(Error.webViewMissing)
        }
        return webView.call(javascript: javascript)
    }

    func sendMessaging(response payload: [String: Any], for messageId: Int) {
        let script = "Zotero.Messaging.receiveResponse('\(messageId)', \(WebViewEncoder.encodeAsJSONForJavascript(payload)));"
        inMainThread { [weak self] in
            self?.webView?.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    func sendHttpResponse(data: Data?, statusCode: Int, url: URL?, successCodes: [Int], headers: [AnyHashable: Any], for messageId: Int) {
        let isSuccess = successCodes.isEmpty ? 200..<300 ~= statusCode : successCodes.contains(statusCode)
        let responseText = data.flatMap({ String(data: $0, encoding: .utf8) }) ?? ""

        var payload: [String: Any]
        if isSuccess {
            payload = ["status": statusCode, "responseText": responseText, "headers": headers, "url": url?.absoluteString ?? ""]
        } else {
            payload = ["error": ["status": statusCode, "responseText": responseText] as [String: Any]]
        }

        sendMessaging(response: payload, for: messageId)
    }

    func sendMessaging(error: String, for messageId: Int) {
        sendMessaging(response: ["error": ["message": error]], for: messageId)
    }

    /// Create single which is fired when webview loads a resource or fails.
    private func createWebLoadedSingle() -> Single<()> {
        return .create { [weak self] subscriber -> Disposable in
            self?.webDidLoad = subscriber
            return Disposables.create {
                self?.webDidLoad = nil
            }
        }
    }

    // MARK: - HTTP Requests

    /// Sends HTTP request based on options. Sends back response with HTTP response to `webView`.
    /// - parameter options: Options for HTTP request.
    func sendRequest(with options: [String: Any], for messageId: Int) throws {
        guard let urlString = options["url"] as? String,
              let url = URL(string: urlString) ?? urlString.removingPercentEncoding.flatMap({ $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap(URL.init) }),
              let method = options["method"] as? String else {
            DDLogInfo("Incorrect URL request from javascript")
            DDLogInfo("\(options)")

            let data = "Incorrect URL request from javascript".data(using: .utf8)
            sendHttpResponse(data: data, statusCode: -1, url: nil, successCodes: [200], headers: [:], for: messageId)
            return
        }

        guard !urlString.contains("repo/code/undefined") else {
            DDLogError("WebViewHandler: Undefined call, translator missing.")

            // Received undefined translator repo call, which happens only when translation doesn't have proper translator available and just gets stuck, so we just force this error here.
            throw Error.urlMissingTranslators
        }

        let headers = (options["headers"] as? [String: String]) ?? [:]
        let body = options["body"] as? String
        let timeout = (options["timeout"] as? Double).flatMap({ $0 / 1000 }) ?? 60
        let successCodes = (options["successCodes"] as? [Int]) ?? []

        DDLogInfo("WebViewHandler: send request to \(url.absoluteString)")

        session.set(cookies: cookies, domain: url.host ?? "")

        var request = URLRequest(url: url)
        request.httpMethod = method
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        if headers["User-Agent"] == nil, let userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        if headers["Referer"] == nil, let referer, !referer.isEmpty {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        request.httpBody = body?.data(using: .utf8)
        request.timeoutInterval = timeout

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if let response = response as? HTTPURLResponse {
                sendHttpResponse(data: data, statusCode: response.statusCode, url: response.url, successCodes: successCodes, headers: response.allHeaderFields, for: messageId)
            } else if let error {
                sendHttpResponse(data: error.localizedDescription.data(using: .utf8), statusCode: -1, url: nil, successCodes: successCodes, headers: [:], for: messageId)
            } else {
                sendHttpResponse(data: "unknown error".data(using: .utf8), statusCode: -1, url: nil, successCodes: successCodes, headers: [:], for: messageId)
            }
        }
        task.resume()
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
        webDidLoad?(.failure(error))
    }
}

/// Communication with JS in `webView`. The `webView` sends a message through one of the registered `JSHandlers`, which is received here.
/// Each message contains a `messageId` in the body, which is used to identify the message in case a response is expected.
extension WebViewHandler: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        inMainThread {
            self.receivedMessageHandler?(message.name, message.body)
        }
    }
}
