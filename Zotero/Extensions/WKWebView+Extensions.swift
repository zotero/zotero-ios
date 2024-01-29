//
//  WKWebView+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 08.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

import CocoaLumberjackSwift
import RxSwift

extension WKWebView {
    /// Makes a javascript call to `webView` with `Single` with result response.
    /// - parameter script: JS script to be performed.
    /// - returns: `Single` with response from `webView`.
    func call(javascript script: String) -> Single<Any> {
        return Single.create { [weak self] subscriber -> Disposable in
            guard let self = self else { return Disposables.create() }

            self.evaluateJavaScript(script) { result, error in
                if let error = error {
                    let nsError = error as NSError

                    // TODO: - Check JS code to see if it's possible to remove this error.
                    // For some calls we get an WKWebView error "JavaScript execution returned a result of an unsupported type" even though no error really occured in the code.
                    // Because of this error the observable doesn't send any more "next" events and we don't receive the response. So we just ignore this error.
                    if nsError.domain == WKErrorDomain && nsError.code == 5 {
                        return
                    }

                    DDLogError("WKWebView: javascript call ('\(script)') error - \(error)")

                    subscriber(.failure(error))
                    return
                }

                if let data = result {
                    subscriber(.success(data))
                } else {
                    subscriber(.success(""))
                }
            }

            return Disposables.create()
        }
    }
}
