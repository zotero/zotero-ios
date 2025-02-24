//
//  HtmlEpubWebView.swift
//  Zotero
//
//  Created by Michal Rentka on 29.01.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

class HtmlEpubWebView: WKWebView {
    private var customMenuActions: [UIAction]

    init(customMenuActions: [UIAction], configuration: WKWebViewConfiguration) {
        self.customMenuActions = customMenuActions
        super.init(frame: .zero, configuration: configuration)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // Allow custom actions
        if action == #selector(customAction(_:)) {
            return true
        }

        return super.canPerformAction(action, withSender: sender)
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        let newMenu = UIMenu(title: "", options: .displayInline, children: customMenuActions)
        builder.insertSibling(newMenu, afterMenu: .standardEdit)
    }

    @objc func customAction(_ sender: Any?) {
        print("Custom action performed!")
    }
}
