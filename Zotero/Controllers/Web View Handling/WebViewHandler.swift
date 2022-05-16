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
    }

    private weak var webView: WKWebView?
    private var webDidLoad: ((SingleEvent<()>) -> Void)?
    var receivedMessageHandler: ((String, Any) -> Void)?

    // MARK: - Lifecycle

    init(webView: WKWebView, javascriptHandlers: [String]?) {
        self.webView = webView

        super.init()

        webView.navigationDelegate = self

        if let handlers = javascriptHandlers {
            handlers.forEach { handler in
                webView.configuration.userContentController.add(self, name: handler)
            }
        }
    }

    // MARK: - Actions

    func load(fileUrl: URL) -> Single<()> {
        guard let webView = self.webView else {
            DDLogError("WebViewHandler: web view is nil")
            return Single.error(Error.webViewMissing)
        }
        webView.loadFileURL(fileUrl, allowingReadAccessTo: fileUrl.deletingLastPathComponent())
        return self.createWebLoadedSingle()
    }

    func load(webUrl: URL) -> Single<()> {
        guard let webView = self.webView else {
            DDLogError("WebViewHandler: web view is nil")
            return Single.error(Error.webViewMissing)
        }
        let request = URLRequest(url: webUrl)
        webView.load(request)
        return self.createWebLoadedSingle()
    }

    func call(javascript: String) -> Single<Any> {
        guard let webView = self.webView else {
            DDLogError("WebViewHandler: web view is nil")
            return Single.error(Error.webViewMissing)
        }
        return webView.call(javascript: javascript)
    }

    func sendMessaging(response payload: [String: Any], for messageId: Int) {
        let script = "Zotero.Messaging.receiveResponse('\(messageId)', \(WKWebView.encodeAsJSONForJavascript(payload)));"
        inMainThread { [weak self] in
            self?.webView?.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    func sendHttpResponse(data: Data?, statusCode: Int, successCodes: [Int], headers: [AnyHashable: Any], for messageId: Int) {
        let isSuccess = successCodes.isEmpty ? 200..<300 ~= statusCode : successCodes.contains(statusCode)
        let responseText = data.flatMap({ String(data: $0, encoding: .utf8) }) ?? ""

        var payload: [String: Any]
        if isSuccess {
            payload = ["status": statusCode, "responseText": responseText, "headers": headers]
        } else {
            payload = ["error": ["status": statusCode, "responseText": responseText]]
        }

        self.sendMessaging(response: payload, for: messageId)
    }

    func sendMessaging(error: String, for messageId: Int) {
        self.sendMessaging(response: ["error": ["message": error]], for: messageId)
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
        self.receivedMessageHandler?(message.name, message.body)
    }
}

