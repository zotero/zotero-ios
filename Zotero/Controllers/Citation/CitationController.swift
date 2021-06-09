//
//  CitationController.swift
//  Zotero
//
//  Created by Michal Rentka on 07.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

import CocoaLumberjackSwift
import RxSwift

class CitationController: NSObject {
    /// Handlers for communication with JS in `webView`
    enum JSHandlers: String, CaseIterable {
        /// Handler used for HTTP requests. Expects response (HTTP response).
        case citation = "citationHandler"
    }

    enum Error: Swift.Error {
        case alreadyRunning
        case cantFindBaseFile
        case missingResponse
        case webViewMissing
    }

    private unowned let stylesController: TranslatorsAndStylesController

    private var webView: WKWebView?
    private var webDidLoad: ((SingleEvent<()>) -> Void)?
    private var webViewCitationResponse: ((SingleEvent<String>) -> Void)?

    init(stylesController: TranslatorsAndStylesController) {
        self.stylesController = stylesController
        super.init()
    }

    func citation(for item: RItem, in controller: UIViewController) -> Single<String> {
        guard self.webView == nil else { return Single.error(Error.alreadyRunning) }


        let webView = self.createWebView(in: controller)
        self.setup(webView: webView)

        return self.load(webView: webView)
                   .flatMap { _ in
                       return self.getCitation()
                   }
                   .do(onSuccess: { [weak self] _ in
                       self?.removeWebView()
                   }, onError: { [weak self] _ in
                       self?.removeWebView()
                   }, onDispose: { [weak self] in
                       self?.removeWebView()
                   })
    }

    // MARK: - Web View

    /// Calls javascript in webView and waits for response.
    /// - returns: Single with citation response or error.
    private func getCitation() -> Single<String> {
        guard let webView = self.webView else { return Single.error(Error.webViewMissing) }
        webView.evaluateJavaScript("getCitation();", completionHandler: nil)
        return Single.create { [weak self] subscriber -> Disposable in
            self?.webViewCitationResponse = subscriber
            return Disposables.create {
                self?.webViewCitationResponse = nil
            }
        }
    }

    /// Loads citation index.html in given web view.
    /// - returns: Single called after index is loaded.
    private func load(webView: WKWebView) -> Single<()> {
        guard let containerUrl = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "citation"),
              let containerHtml = try? String(contentsOf: containerUrl, encoding: .utf8) else {
            DDLogError("CitationController: can't load citation html")
            return Single.error(Error.cantFindBaseFile)
        }
        return self.load(html: containerHtml, baseUrl: containerUrl, webView: webView)
    }

    /// Loads given html string in given web view.
    /// - returns: Single called after html is loaded.
    private func load(html: String, baseUrl: URL, webView: WKWebView) -> Single<()> {
        webView.loadHTMLString(html, baseURL: baseUrl)
        return self.createWebLoadedSingle()
    }

    /// Create new `WKWebView` instance in given controller.
    /// - returns: WebView instance.
    private func createWebView(in controller: UIViewController) -> WKWebView {
        let webView = WKWebView()
        webView.isHidden = true
        controller.view.addSubview(webView)
        self.webView = webView
        return webView
    }

    /// Create single which is fired when webview loads a resource or fails.
    /// - returns: Single called after webView is loaded.
    private func createWebLoadedSingle() -> Single<()> {
        return Single.create { [weak self] subscriber -> Disposable in
            self?.webDidLoad = subscriber
            return Disposables.create {
                self?.webDidLoad = nil
            }
        }
    }

    /// Setup web view with delegate and js handlers for communication.
    private func setup(webView: WKWebView) {
        webView.navigationDelegate = self
        JSHandlers.allCases.forEach { handler in
            webView.configuration.userContentController.add(self, name: handler.rawValue)
        }
    }

    /// Remove web view from parent controller.
    private func removeWebView() {
        self.webView?.removeFromSuperview()
        self.webView = nil
    }
}

extension CitationController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Wait for javascript to load
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            self.webDidLoad?(.success(()))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Swift.Error) {
        DDLogError("CitationController: failed to load webview - \(error)")
        self.webDidLoad?(.failure(error))
    }
}

/// Communication with JS in `webView`. The `webView` sends a message through one of the registered `JSHandlers`, which is received here.
extension CitationController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let handler = JSHandlers(rawValue: message.name) else { return }

        switch handler {
        case .citation:
            if let citation = message.body as? String {
                self.webViewCitationResponse?(.success(citation))
            } else {
                self.webViewCitationResponse?(.failure(Error.missingResponse))
            }
        }
    }
}
