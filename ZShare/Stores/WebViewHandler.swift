//
//  WebViewHandler.swift
//  ZShare
//
//  Created by Michal Rentka on 05/12/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import WebKit

import RxSwift

class WebViewHandler: NSObject {
    struct JSHandlers {
        static let request = "requestHandler"
        static let item = "itemResponseHandler"
    }

    enum Error: Swift.Error {
        case cantFindBaseFile
        case jsError(String)
    }

    private let apiClient: ApiClient
    private let translatorsController: TranslatorsController
    private let disposeBag: DisposeBag
    let observable: PublishSubject<[[String: Any]]>

    private weak var webView: WKWebView!
    private var webDidLoad: ((SingleEvent<()>) -> Void)?

    // MARK: - Lifecycle

    init(webView: WKWebView, apiClient: ApiClient, fileStorage: FileStorage) {
        self.webView = webView
        self.apiClient = apiClient
        self.disposeBag = DisposeBag()
        self.translatorsController = TranslatorsController(fileStorage: fileStorage)
        self.observable = PublishSubject()

        super.init()

        webView.configuration.userContentController.add(self, name: JSHandlers.request)
        webView.configuration.userContentController.add(self, name: JSHandlers.item)
    }

    // MARK: - Loading translation server

    /// Runs translation server against html content with cookies. Results are then provided through observable publisher.
    /// - parameter url: Original URL of shared website.
    /// - parameter title: Title of the shared website.
    /// - parameter html: HTML content of the shared website. Equals to javascript "document.documentElement.innerHTML".
    /// - parameter cookies: Cookies string from shared website. Equals to javacsript "document.cookie".
    func translate(url: URL, title: String, html: String, cookies: String) {
        guard let containerUrl = Bundle.main.url(forResource: "src/index", withExtension: "html", subdirectory: "translation"),
              let containerHtml = try? String(contentsOf: containerUrl, encoding: .utf8) else {
            self.observable.on(.error(Error.cantFindBaseFile))
            return
        }

        var encodedHtml = html.data(using: .utf8)?.base64EncodedString(options: .endLineWithLineFeed) ?? "null"
        encodedHtml = encodedHtml != "null" ? "'\(encodedHtml)'" : encodedHtml

        return self.loadCookies(from: cookies)
                   .flatMap { _ -> Single<()> in
                       return self.loadHtml(content: containerHtml, baseUrl: containerUrl)
                   }
                   .flatMap { _ -> Single<[TranslatorInfo]> in
                       return self.translatorsController.load()
                   }
                   .flatMap { translators -> Single<Any> in
                       let translatorData = try? JSONSerialization.data(withJSONObject: translators, options: .prettyPrinted)
                       var encodedTranslators = translatorData?.base64EncodedString(options: .endLineWithLineFeed) ?? "null"
                       encodedTranslators = encodedTranslators != "null" ? "'\(encodedTranslators)'" : encodedTranslators
                       return self.callJavascript("translate('\(url.absoluteString)', '\(cookies)', \(encodedHtml), \(encodedTranslators));")
                   }
                   .subscribe(onError: { [weak self] error in
                       self?.observable.on(.error(error))
                   })
                   .disposed(by: self.disposeBag)
    }

    private func loadHtml(content: String, baseUrl: URL) -> Single<()> {
        self.webView.navigationDelegate = self
        self.webView.loadHTMLString(content, baseURL: baseUrl)

        return Single.create { subscriber -> Disposable in
            self.webDidLoad = subscriber
            return Disposables.create()
        }
    }

    private func loadCookies(from string: String) -> Single<()> {
        return Single.create { subscriber -> Disposable in
            let cookies = string.split(separator: ";").compactMap { pair -> HTTPCookie? in
                let keyValue = pair.split(separator: "=")
                guard keyValue.count == 2 else { return nil }
                return HTTPCookie(properties: [.name: keyValue[0], .value: keyValue[1]])
            }

            let group = DispatchGroup()

            cookies.forEach { cookie in
                group.enter()
                self.webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                    group.leave()
                }
            }

            group.notify(qos: .utility, flags: [], queue: .global()) {
                subscriber(.success(()))
            }
            return Disposables.create()
        }
    }

    // MARK: - Communication with WKWebView

    private func sendRequest(with options: [String: Any]) {
        guard let request = JSRequest(options: options) else { return }

        self.apiClient.send(request: request)
                      .subscribe(onSuccess: { [weak self] data, headers in
                          self?.webView.evaluateJavaScript("responseSucceeded('data')", completionHandler: nil)
                      }, onError: { [weak self] error in
                          self?.webView.evaluateJavaScript("responseFailed('error')", completionHandler: nil)
                      })
                      .disposed(by: self.disposeBag)
    }

    private func receiveItem(with info: [String: Any]) {
        if let error = info["error"] as? String {
            self.observable.on(.error(Error.jsError(error)))
            return
        }
        self.observable.on(.next([info]))
    }

    // MARK: - Helpers

    private func callJavascript(_ script: String) -> Single<Any> {
        return Single.create { subscriber -> Disposable in
            self.webView.evaluateJavaScript(script) { result, error in
                if let data = result {
                    subscriber(.success(data))
                } else {
                    subscriber(.error(error ?? Error.jsError("Unknown error")))
                }
            }

            return Disposables.create()
        }
    }
}

extension WebViewHandler: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.webDidLoad?(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Swift.Error) {
        self.webDidLoad?(.error(error))
    }
}

extension WebViewHandler: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case JSHandlers.request:
            if let options = message.body as? [String: Any] {
                self.sendRequest(with: options)
            }

        case JSHandlers.item:
            if let info = message.body as? [String: Any] {
                self.receiveItem(with: info)
            }

        default: return
        }
    }
}
