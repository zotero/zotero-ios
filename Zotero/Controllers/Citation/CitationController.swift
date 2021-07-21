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
    enum Format: String {
        case html = "html"
    }

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
        case prepareNotCalled
    }

    private unowned let stylesController: TranslatorsAndStylesController
    private unowned let fileStorage: FileStorage
    private unowned let dbStorage: DbStorage
    private let backgroundScheduler: SerialDispatchQueueScheduler

    private var webView: WKWebView?
    private var styleXml: String?
    private var localeId: String?
    private var localeXml: String?

    private var webDidLoad: ((SingleEvent<()>) -> Void)?
    private var webViewResponse: ((SingleEvent<String>) -> Void)?

    init(stylesController: TranslatorsAndStylesController, fileStorage: FileStorage, dbStorage: DbStorage) {
        self.stylesController = stylesController
        self.fileStorage = fileStorage
        self.dbStorage = dbStorage
        self.backgroundScheduler = SerialDispatchQueueScheduler(internalSerialQueueName: "org.zotero.CitationController")
        super.init()
    }

    // MARK: - Actions

    /// Pre-loads given webView with appropriate index.html so that it's ready immediately for preview generation.
    /// - parameter styleId: Id of style to use for citation generation.
    /// - parameter localeId: Id of locale to use for citation generation.
    /// - returns: Single which is called when webView is fully loaded.
    func prepareForCitation(styleId: String, localeId: String, in webView: WKWebView) -> Single<()> {
        webView.navigationDelegate = self
        JSHandlers.allCases.forEach { handler in
            webView.configuration.userContentController.add(self, name: handler.rawValue)
        }

        return self.loadStyleFilename(for: styleId)
                    .subscribe(on: self.backgroundScheduler)
                    .observe(on: self.backgroundScheduler)
                    .flatMap({ filename -> Single<(String, String)> in
                        return self.loadEncodedXmls(styleFilename: filename, localeId: localeId)
                    })
                    .do(onSuccess: { style, locale in
                        self.styleXml = style
                        self.localeId = localeId
                        self.localeXml = locale
                    })
                    .flatMap({ _ -> Single<(String, URL)> in
                        return self.loadIndexHtml()
                    })
                    .observe(on: MainScheduler.instance)
                    .flatMap({ [weak webView] html, url -> Single<()> in
                         guard let webView = webView else { return Single.error(Error.deinitialized) }
                         return self.load(html: html, baseUrl: url, in: webView).flatMap({ _ in Single.just(()) })
                    })
    }

    /// Generates citation preview for given item in given format. Has to be called after `prepareForCitation(styleId:localeId:in:)` finishes!
    /// - parameter item: Item for which citation is generated.
    /// - parameter label: Label for locator which should be used.
    /// - parameter locator: Locator value.
    /// - parameter omitAuthor: True if author should be suppressed, false otherwise.
    /// - parameter format: Format in which citation is generated.
    /// - parameter webView: Web view which is fully loaded (`prepareForCitation(styleId:localeId:in:)` finished).
    /// - returns: Single with generated citation.
    func citation(for item: RItem, label: String?, locator: String?, omitAuthor: Bool, format: Format, in webView: WKWebView) -> Single<String> {
        guard let style = self.styleXml, let localeId = self.localeId, let locale = self.localeXml else { return Single.error(Error.prepareNotCalled) }
        return self.getCitation(styleXml: style, localeId: localeId, localeXml: locale, label: label, locator: locator, omitAuthor: omitAuthor, format: format.rawValue, webView: webView)
    }

    /// Cleans up after citation. Should be called when all citation() requests are called.
    func finishCitation() {
        self.localeXml = nil
        self.styleXml = nil
    }

    /// Bibliography happens once for selected item(s). Appropriate style and locale xmls are loaded, webView is initialized and loaded with index.html. When everything is loaded,
    /// appropriate js function is called and result is returned. When everything is finished, webView is removed from controller.
    /// - parameter item: Item for which bibliography is created.
    /// - parameter styleId: Id of style to use for bibliography generation.
    /// - parameter localeId: Id of locale to use for bibliography generation.
    /// - parameter format: Bibliography format to use for generation.
    /// - parameter webView: WebView which will run the javascript.
    /// - returns: Single which returns bibliography.
    func bibliography(for item: RItem, styleId: String, localeId: String, format: Format, in webView: WKWebView) -> Single<String> {
        webView.navigationDelegate = self
        JSHandlers.allCases.forEach { handler in
            webView.configuration.userContentController.add(self, name: handler.rawValue)
        }

        return self.loadStyleFilename(for: styleId)
                   .subscribe(on: self.backgroundScheduler)
                   .observe(on: self.backgroundScheduler)
                   .flatMap({ filename -> Single<(String, String)> in
                       return self.loadEncodedXmls(styleFilename: filename, localeId: localeId)
                   })
                   .flatMap({ style, locale -> Single<(String, String, String, URL)> in
                       return self.loadIndexHtml().flatMap({ Single.just((style, locale, $0, $1)) })
                   })
                  .observe(on: MainScheduler.instance)
                  .flatMap({ [weak webView] style, locale, html, url -> Single<(String, String)> in
                      guard let webView = webView else { return Single.error(Error.deinitialized) }
                      return self.load(html: html, baseUrl: url, in: webView).flatMap({ Single.just((style, locale)) })
                  })
                  .flatMap({ [weak webView] style, locale in
                      guard let webView = webView else { return Single.error(Error.deinitialized) }
                      return self.getBibliography(styleXml: style, localeId: localeId, localeXml: locale, format: format.rawValue, webView: webView)
                  })
    }

    private func loadEncodedXmls(styleFilename: String, localeId: String) -> Single<(String, String)> {
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

    private func loadStyleFilename(for styleId: String) -> Single<String> {
        return Single.create { subscriber in
            do {
                let style = try self.dbStorage.createCoordinator().perform(request: ReadStyleDbRequest(identifier: styleId))
                subscriber(.success(style.filename))
            } catch let error {
                DDLogError("CitationController: can't load style - \(error)")
                subscriber(.failure(Error.styleOrLocaleMissing))
            }
            return Disposables.create()
        }
    }

    // MARK: - Web View

    /// Calls javascript in webView and waits for response.
    /// - returns: Single with citation response or error.
    private func getCitation(styleXml: String, localeId: String, localeXml: String, label: String?, locator: String?, omitAuthor: Bool, format: String, webView: WKWebView) -> Single<String> {
        webView.evaluateJavaScript("getCit(\(styleXml), '\(localeId)', \(localeXml), '\(format)', \(WKWebView.optionalToJs(label)), \(WKWebView.optionalToJs(locator)), \(omitAuthor));",
                                   completionHandler: nil)

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
    private func load(html: String, baseUrl: URL, in webView: WKWebView) -> Single<()> {
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
