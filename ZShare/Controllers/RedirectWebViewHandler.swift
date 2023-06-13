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

final class RedirectWebViewHandler: NSObject {
    private let initialUrl: URL
    private let timeout: RxTimeInterval
    private let timerScheduler: SerialDispatchQueueScheduler

    private weak var webView: WKWebView?
    private var completionHandler: RedirectWebViewCompletion?
    private var disposeBag: DisposeBag?

    init(url: URL, timeoutPerRedirect timeout: RxTimeInterval, webView: WKWebView) {
        self.initialUrl = url
        self.timeout = timeout
        self.webView = webView
        self.timerScheduler = SerialDispatchQueueScheduler(internalSerialQueueName: "org.zotero.RedirectWebViewHandler.TimerScheduler")

        super.init()
        
        webView.navigationDelegate = self
    }

    func getPdfUrl(completion: @escaping RedirectWebViewCompletion) {
        guard let webView = self.webView else {
            completion(nil, nil, nil, nil)
            return
        }

        self.completionHandler = completion
        webView.load(URLRequest(url: self.initialUrl))
    }

    private func startTimer() {
        let disposeBag = DisposeBag()
        self.disposeBag = disposeBag

        Single<Int>.timer(self.timeout, scheduler: self.timerScheduler)
                   .observe(on: MainScheduler.instance)
                   .subscribe(onSuccess: { [weak self] _ in
                       guard let self = self else { return }

                       DDLogInfo("RedirectWebViewHandler: redirection timed out")

                       self.webView?.stopLoading()
                       if let completion = self.completionHandler {
                           completion(nil, nil, nil, nil)
                           self.completionHandler = nil
                       }
                   })
                   .disposed(by: disposeBag)
    }

    private func extractData(from webView: WKWebView, completion: @escaping (String?, String?, String?) -> Void) {
        guard let url = Bundle.main.url(forResource: "webview_extraction", withExtension: "js"),
              let script = try? String(contentsOf: url) else {
            DDLogError("RedirectWebViewHandler: can't load extraction javascript")
            completion(nil, nil, nil)
            return
        }

        DDLogInfo("RedirectWebViewHandler: call data extraction js")

        let disposeBag = DisposeBag()
        webView.call(javascript: script)
               .observe(on: MainScheduler.instance)
               .subscribe(with: self, onSuccess: { `self`, data in
                   self.disposeBag = nil

                   guard let payload = data as? [String: Any],
                         let cookies = payload["cookies"] as? String,
                         let userAgent = payload["userAgent"] as? String,
                         let referrer = payload["referrer"] as? String else {
                       DDLogError("RedirectWebViewHandler: extracted data missing response")
                       DDLogError("\(data as? [String: Any])")
                       completion(nil, nil, nil)
                       return
                   }

                   completion(cookies, userAgent, referrer)
               }, onFailure: { `self`, _ in
                   self.disposeBag = nil
                   completion(nil, nil, nil)
               })
               .disposed(by: disposeBag)
        self.disposeBag = disposeBag
    }
}

extension RedirectWebViewHandler: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard let mimeType = navigationResponse.response.mimeType else {
            self.startTimer()
            decisionHandler(.allow)
            return
        }

        switch mimeType {
        case "application/pdf":
            DDLogInfo("RedirectWebViewHandler: redirection detected pdf - \(navigationResponse.response.url?.absoluteString ?? "-")")
            inMainThread { [weak self, weak webView] in
                guard let self = self, let webView = webView else { return }

                // Cancel timer
                self.disposeBag = nil

                // Extract webView data
                self.extractData(from: webView) { cookies, userAgent, referrer in
                    // Return url
                    self.completionHandler?(navigationResponse.response.url, cookies, userAgent, referrer)
                    self.completionHandler = nil
                }
            }
            // Don't load web
            decisionHandler(.cancel)

        default:
            self.startTimer()
            decisionHandler(.allow)
        }
    }
}
