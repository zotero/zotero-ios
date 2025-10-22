//
//  WebViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 20/10/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

final class WebViewController: UIViewController {
    private let url: URL

    private var webView: WKWebView? {
        return self.view as? WKWebView
    }

    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let view = WKWebView()
        view.allowsBackForwardNavigationGestures = true
        view.navigationDelegate = self
        self.view = view
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupNavigationBar()

        if self.url.scheme == "file" {
            self.webView?.loadFileURL(self.url, allowingReadAccessTo: self.url)
        } else {
            let request = URLRequest(url: self.url)
            self.webView?.load(request)
        }
    }

    private func setupNavigationBar() {
        let primaryAction = UIAction(title: L10n.close) { [weak self] _ in
            self?.dismiss(animated: true)
        }
        let closeItem: UIBarButtonItem
        if #available(iOS 26.0.0, *) {
            closeItem = UIBarButtonItem(systemItem: .close, primaryAction: primaryAction)
        } else {
            closeItem = UIBarButtonItem(primaryAction: primaryAction)
        }
        navigationItem.leftBarButtonItem = closeItem
    }
}

extension WebViewController: WKNavigationDelegate {}
