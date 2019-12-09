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
    enum Error: Swift.Error {
        case cantFindBaseFile, translation
    }

    private weak var webView: WKWebView!
    private var webDidLoad: ((SingleEvent<()>) -> Void)?

    init(webView: WKWebView) {
        self.webView = webView
    }

    /// Runs translation server against html content with cookies. Loads documents and returns their urls in completion handler.
    /// - parameter url: Original URL of shared website.
    /// - parameter title: Title of the shared website.
    /// - parameter html: HTML content of the shared website. Equals to javascript "document.documentElement.innerHTML".
    /// - parameter cookies: Cookies string from shared website. Equals to javacsript "document.cookie".
    /// - returns: Returns a Single with detected urls.
    func loadDocument(for url: URL, title: String, html: String, cookies: String) -> Single<[URL]> {
        guard let containerUrl = Bundle.main.url(forResource: "src/index", withExtension: "html", subdirectory: "translation"),
              let containerHtml = try? String(contentsOf: containerUrl, encoding: .utf8) else {
            return Single.error(Error.cantFindBaseFile)
        }

        let escapedHtml = String(html.components(separatedBy: .newlines).joined()).replacingOccurrences(of: "\"", with: "\\\"")

        return self.loadCookies(from: cookies)
                   .flatMap { _ -> Single<()> in
                       return self.loadHtml(content: containerHtml, baseUrl: containerUrl)
                   }
                   .flatMap { _ -> Single<Any> in
                       return self.callJavascript("document.querySelector('#url').value=\"\(url.absoluteString)\";")
                   }
                   .flatMap { data -> Single<Any> in
                       return self.callJavascript("document.querySelector('#html').innerHTML=\"\(escapedHtml)\";")
                   }
                   .flatMap { data -> Single<[URL]> in
                       if let data = data as? [String: Any] {
                           // TODO: - convert results
                           return Single.just([])
                       } else {
                           return Single.error(Error.translation)
                       }
                   }
    }

    private func callJavascript(_ script: String) -> Single<Any> {
        return Single.create { subscriber -> Disposable in
            self.webView.evaluateJavaScript(script) { result, error in
                if let data = result {
                    subscriber(.success(data))
                } else {
                    subscriber(.error(error ?? Error.translation))
                }
            }

            return Disposables.create()
        }
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
}

extension WebViewHandler: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.webDidLoad?(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Swift.Error) {
        self.webDidLoad?(.error(error))
    }
}
