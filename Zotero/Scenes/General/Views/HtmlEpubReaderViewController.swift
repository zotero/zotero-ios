//
//  HtmlEpubReaderViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 24.08.2023.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

import CocoaLumberjackSwift
import RxSwift

class HtmlEpubReaderViewController: UIViewController {
    private let url: URL
    private let disposeBag: DisposeBag

    private weak var webView: WKWebView!

    init(url: URL) {
        self.url = url
        self.disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupNavigationBar()
        self.setupWebView()
    }

    // MARK: - Actions

    private func close() {
        self.navigationController?.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    // MARK: - Setups

    private func setupWebView() {
        let webView = WKWebView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(webView)

        NSLayoutConstraint.activate([
            self.view.safeAreaLayoutGuide.topAnchor.constraint(equalTo: webView.topAnchor),
            self.view.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
            self.view.safeAreaLayoutGuide.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            self.view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: webView.trailingAnchor)
        ])
        self.webView = webView

        guard let url = Bundle.main.url(forResource: "view", withExtension: "html", subdirectory: "Bundled/reader") else {
            DDLogError("HtmlEpubReaderViewController: can't load reader view.html")
            return
        }

        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    private func setupNavigationBar() {
        let closeButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: nil, action: nil)
        closeButton.title = L10n.close
        closeButton.accessibilityLabel = L10n.close
        closeButton.rx.tap.subscribe(with: self, onNext: { `self`, _ in self.close() }).disposed(by: self.disposeBag)
        self.navigationItem.leftBarButtonItem = closeButton
    }
}
