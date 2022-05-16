//
//  LookupWebViewHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 16.05.2022.
//  Copyright © 2022 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation
import WebKit

final class LookupWebViewHandler {
    private let webViewHandler: WebViewHandler

    init(webView: WKWebView) {
        self.webViewHandler = WebViewHandler(webView: webView, javascriptHandlers: nil)
    }
}
