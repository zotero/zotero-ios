//
//  WebViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 20/10/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

import RxSwift

class WebViewController: UIViewController {
    private let url: URL
    private let disposeBag: DisposeBag

    private var webView: WKWebView? {
        return self.view as? WKWebView
    }

    init(url: URL) {
        self.url = url
        self.disposeBag = DisposeBag()
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
        let close = UIBarButtonItem(title: L10n.cancel, style: .plain, target: nil, action: nil)
        close.rx.tap
             .subscribe(onNext: { [weak self] in
                 self?.dismiss(animated: true, completion: nil)
             })
             .disposed(by: self.disposeBag)
        self.navigationItem.leftBarButtonItem = close
    }
}

extension WebViewController: WKNavigationDelegate {}
