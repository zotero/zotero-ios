//
//  CopyBibliographyAction.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 27/12/23.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

enum CopyBibliographyAction {
    case preload(WKWebView)
    case cleanup
}
