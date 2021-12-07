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

typealias RedirectWebViewCompletion = (URL?) -> Void

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
            completion(nil)
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
                       guard let `self` = self else { return }

                       DDLogInfo("RedirectWebViewHandler: redirection timed out")

                       self.webView?.stopLoading()
                       if let completion = self.completionHandler {
                           completion(nil)
                           self.completionHandler = nil
                       }
                   })
                   .disposed(by: disposeBag)

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

            // Don't load web
            decisionHandler(.cancel)
            // Cancel timer
            self.disposeBag = nil
            // Return url
            self.completionHandler?(navigationResponse.response.url)
        default:
            self.startTimer()
            decisionHandler(.allow)
        }
    }
}
