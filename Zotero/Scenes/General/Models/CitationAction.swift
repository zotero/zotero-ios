//
//  CitationAction.swift
//  Zotero
//
//  Created by Michal Rentka on 15.06.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

enum CitationAction {
    case preload(WKWebView)
    case setLocator(String)
    case setLocatorValue(String)
    case setOmitAuthor(Bool)
    case cleanup
    case copy
}
