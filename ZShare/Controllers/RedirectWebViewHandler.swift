//
//  RedirectWebViewHandler.swift
//  ZShare
//
//  Created by Michal Rentka on 03.12.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

import CocoaLumberjackSwift
import RxSwift

typealias RedirectWebViewCompletion = (URL?, String?, String?, String?) -> Void
typealias RedirectWebViewTimeout = () -> Void

final class RedirectWebViewHandler: NSObject {
    private let initialUrl: URL
    private let timeout: RxTimeInterval
    private let timerScheduler: SerialDispatchQueueScheduler

    private weak var webView: WKWebView?
    private var completionHandler: RedirectWebViewCompletion?
    private var timeoutHandler: RedirectWebViewTimeout?
    private var disposeBag: DisposeBag?

    init(url: URL, timeoutPerRedirect timeout: RxTimeInterval, webView: WKWebView) {
        initialUrl = url
        self.timeout = timeout
        self.webView = webView
        timerScheduler = SerialDispatchQueueScheduler(internalSerialQueueName: "org.zotero.RedirectWebViewHandler.TimerScheduler")

        super.init()
        
        webView.navigationDelegate = self
    }

    func getPdfUrl(completion: @escaping RedirectWebViewCompletion, timeout: @escaping RedirectWebViewTimeout) {
        guard let webView else {
            completion(nil, nil, nil, nil)
            return
        }

        completionHandler = completion
        timeoutHandler = timeout
        webView.load(URLRequest(url: initialUrl))
    }
}

extension RedirectWebViewHandler: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard let mimeType = navigationResponse.response.mimeType else {
            startTimer()
            decisionHandler(.allow)
            return
        }

        switch mimeType {
        case "application/pdf":
            DDLogInfo("RedirectWebViewHandler: redirection detected pdf - \(navigationResponse.response.url?.absoluteString ?? "-")")
            inMainThread { [weak self, weak webView] in
                guard let self, let webView else { return }

                // Cancel timer
                disposeBag = nil

                // Extract webView data
                extractData(from: webView) { [weak self] cookies, userAgent, referrer in
                    guard let self else { return }
                    // Return url
                    completionHandler?(navigationResponse.response.url, cookies, userAgent, referrer)
                    completionHandler = nil
                }
            }
            // Don't load web
            decisionHandler(.cancel)

        default:
            startTimer()
            decisionHandler(.allow)
        }

        func startTimer() {
            let disposeBag = DisposeBag()
            self.disposeBag = disposeBag

            Single<Int>.timer(timeout, scheduler: timerScheduler)
                .observe(on: MainScheduler.instance)
                .subscribe(onSuccess: { [weak self] _ in
                    guard let self else { return }

                    DDLogInfo("RedirectWebViewHandler: redirection timed out")

                    timeoutHandler?()
                    timeoutHandler = nil
                })
                .disposed(by: disposeBag)
        }

        func extractData(from webView: WKWebView, completion: @escaping (String?, String?, String?) -> Void) {
            guard let url = Bundle.main.url(forResource: "webview_extraction", withExtension: "js"), let script = try? String(contentsOf: url) else {
                DDLogError("RedirectWebViewHandler: can't load extraction javascript")
                completion(nil, nil, nil)
                return
            }

            DDLogInfo("RedirectWebViewHandler: call data extraction js")

            let disposeBag = DisposeBag()
            self.disposeBag = disposeBag
            webView.call(javascript: script)
                .observe(on: MainScheduler.instance)
                .subscribe(onSuccess: { [weak self] data in
                    self?.disposeBag = nil

                    guard let payload = data as? [String: Any],
                          let cookies = payload["cookies"] as? String,
                          let userAgent = payload["userAgent"] as? String,
                          let referrer = payload["referrer"] as? String else {
                        DDLogError("RedirectWebViewHandler: extracted data missing response")
                        DDLogError("\(String(describing: data as? [String: Any]))")
                        completion(nil, nil, nil)
                        return
                    }

                    completion(cookies, userAgent, referrer)
                }, onFailure: { [weak self] _ in
                    self?.disposeBag = nil
                    completion(nil, nil, nil)
                })
                .disposed(by: disposeBag)
        }
    }
}
