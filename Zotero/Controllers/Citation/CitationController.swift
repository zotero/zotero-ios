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
        case log = "logHandler"
        case bibliography = "bibliographyHandler"
    }

    enum Error: Swift.Error {
        case deinitialized
        case alreadyRunning
        case cantFindBaseFile
        case missingResponse
        case styleOrLocaleMissing
    }

    private unowned let stylesController: TranslatorsAndStylesController
    private unowned let fileStorage: FileStorage
    private let backgroundScheduler: SerialDispatchQueueScheduler

    private var webView: WKWebView?
    private var webDidLoad: ((SingleEvent<WKWebView>) -> Void)?
    private var webViewResponse: ((SingleEvent<String>) -> Void)?

    init(stylesController: TranslatorsAndStylesController, fileStorage: FileStorage) {
        self.stylesController = stylesController
        self.fileStorage = fileStorage
        self.backgroundScheduler = SerialDispatchQueueScheduler(internalSerialQueueName: "org.zotero.CitationController")
        super.init()
    }

    // MARK: - Actions

    func citation(for item: RItem, styleFilename: String, localeId: String, format: CitationFormat, in controller: UIViewController) -> Single<String> {
        return self.loadEncodedXmls(styleFilename: styleFilename, localeId: localeId)
                   .subscribe(on: self.backgroundScheduler)
                   .flatMap({ styleXml, localeXml -> Single<String> in
                       return self.call(webViewAction: { self.getCitation(styleXml: styleXml, localeId: localeId, localeXml: localeXml, format: format.rawValue, webView: $0) }, in: controller)
                   })
    }

    func bibliography(for item: RItem, styleFilename: String, localeId: String, format: CitationFormat, in controller: UIViewController) -> Single<String> {
        return self.loadEncodedXmls(styleFilename: styleFilename, localeId: localeId)
                   .subscribe(on: self.backgroundScheduler)
                   .flatMap({ styleXml, localeXml -> Single<String> in
                       return self.call(webViewAction: { self.getBibliography(styleXml: styleXml, localeId: localeId, localeXml: localeXml, format: format.rawValue, webView: $0) }, in: controller)
                   })
    }

    private func call<Response>(webViewAction: @escaping (WKWebView) -> Single<Response>, in controller: UIViewController) -> Single<Response> {
        guard self.webView == nil else { return Single.error(Error.alreadyRunning) }

        return self.loadIndexHtml()
                   .subscribe(on: self.backgroundScheduler)
                   .observe(on: MainScheduler.instance)
                   .flatMap({ html, url -> Single<(WKWebView, String, URL)> in
                       return self.setupWebView(in: controller).flatMap({ Single.just(($0, html, url)) })
                   })
                   .flatMap({ webView, html, url in
                       return self.load(html: html, baseUrl: url, in: webView)
                   })
                   .flatMap { webView -> Single<Response> in
                       return webViewAction(webView)
                   }
                   .do(onSuccess: { [weak self] _ in
                       self?.removeWebView()
                   }, onError: { [weak self] _ in
                       self?.removeWebView()
                   }, onDispose: { [weak self] in
                       self?.removeWebView()
                   })
    }

    private func loadEncodedXmls(styleFilename: String, localeId: String) -> Single<(style: String, locale: String)> {
        return Single.create { subscriber in
            guard let localeUrl = Bundle.main.url(forResource: "locales-\(localeId)", withExtension: "xml", subdirectory: "Bundled/locales") else {
                DDLogError("CitationController: can't load locale xml")
                subscriber(.failure(Error.styleOrLocaleMissing))
                return Disposables.create()
            }

            do {
                let localeData = try Data(contentsOf: localeUrl)
                let styleData = try self.fileStorage.read(Files.style(filename: styleFilename))

                subscriber(.success((WKWebView.encodeForJavascript(styleData), WKWebView.encodeForJavascript(localeData))))

            } catch let error {
                DDLogError("CitationController: can't read locale or style - \(error)")
                subscriber(.failure(Error.styleOrLocaleMissing))
            }

            return Disposables.create()
        }
    }

    // MARK: - Web View

    /// Calls javascript in webView and waits for response.
    /// - returns: Single with citation response or error.
    private func getCitation(styleXml: String, localeId: String, localeXml: String, format: String, webView: WKWebView) -> Single<String> {
        webView.evaluateJavaScript("getCit(\(styleXml), '\(localeId)', \(localeXml), '\(format)');", completionHandler: nil)

        return Single.create { [weak self] subscriber -> Disposable in
            self?.webViewResponse = subscriber
            return Disposables.create {
                self?.webViewResponse = nil
            }
        }
    }

    /// Calls javascript in webView and waits for response.
    /// - returns: Single with bibliography response or error.
    private func getBibliography(styleXml: String, localeId: String, localeXml: String, format: String, webView: WKWebView) -> Single<String> {
        webView.evaluateJavaScript("getBib(\(styleXml), '\(localeId)', \(localeXml), '\(format)');", completionHandler: nil)

        return Single.create { [weak self] subscriber -> Disposable in
            self?.webViewResponse = subscriber
            return Disposables.create {
                self?.webViewResponse = nil
            }
        }
    }

    /// Loads html in given web view.
    /// - returns: Single called after index is loaded.
    private func load(html: String, baseUrl: URL, in webView: WKWebView) -> Single<WKWebView> {
        webView.loadHTMLString(html, baseURL: baseUrl)

        return Single.create { [weak self] subscriber -> Disposable in
            self?.webDidLoad = subscriber
            return Disposables.create {
                self?.webDidLoad = nil
            }
        }
    }

    private func loadIndexHtml() -> Single<(String, URL)> {
        return Single.create { subscriber in
            guard let containerUrl = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "citation"),
                  let containerHtml = try? String(contentsOf: containerUrl, encoding: .utf8) else {
                DDLogError("CitationController: can't load citation html")
                subscriber(.failure(Error.cantFindBaseFile))
                return Disposables.create()
            }
            subscriber(.success((containerHtml, containerUrl)))
            return Disposables.create()
        }
    }

    /// Create new `WKWebView` instance in given controller and sets it up with js handlers.
    /// - returns: WebView instance.
    private func setupWebView(in controller: UIViewController) -> Single<WKWebView> {
        return Single.create { [weak controller, weak self] subscriber -> Disposable in
            guard let controller = controller, let `self` = self else {
                subscriber(.failure(Error.deinitialized))
                return Disposables.create()
            }

            let webView = WKWebView()
            webView.isHidden = true
            webView.navigationDelegate = self
            JSHandlers.allCases.forEach { handler in
                webView.configuration.userContentController.add(self, name: handler.rawValue)
            }

            controller.view.addSubview(webView)

            subscriber(.success(webView))
            return Disposables.create()
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
            self.webDidLoad?(.success(webView))
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
        case .citation, .bibliography:
            if let citation = message.body as? String {
                self.webViewResponse?(.success(citation))
            } else {
                self.webViewResponse?(.failure(Error.missingResponse))
            }

        case .log:
            DDLogInfo("CitationController: \((message.body as? String) ?? "-")")
        }
    }
}
