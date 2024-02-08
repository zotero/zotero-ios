//
//  SingleCitationAction.swift
//  Zotero
//
//  Created by Michal Rentka on 15.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

enum SingleCitationAction {
    case preload(webView: WKWebView)
    case setLocator(locator: String, webView: WKWebView)
    case setLocatorValue(value: String, webView: WKWebView)
    case setOmitAuthor(omitAuthor: Bool, webView: WKWebView)
    case setPreviewHeight(CGFloat)
    case cleanup
    case copy(webView: WKWebView)
}
