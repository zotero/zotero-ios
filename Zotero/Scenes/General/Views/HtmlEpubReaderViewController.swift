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
    enum JSHandlers: String, CaseIterable {
        case text = "textHandler"
        case log = "logHandler"
    }

    private let url: URL
    private let disposeBag: DisposeBag

    private weak var webView: WKWebView!
    private var webViewHandler: WebViewHandler!

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
        self.load()
    }

    // MARK: - Actions

    private func load() {
        guard let readerUrl = Bundle.main.url(forResource: "view", withExtension: "html", subdirectory: "Bundled/reader") else {
            DDLogError("HtmlEpubReaderViewController: can't load reader view.html")
            return
        }
        self.webViewHandler.load(fileUrl: readerUrl)
            .subscribe()
            .disposed(by: self.disposeBag)
    }

    private func process(handler: String, message: Any) {
        switch handler {
        case JSHandlers.log.rawValue:
            DDLogInfo("HtmlEpubReaderViewController: JSLOG \(message)")

        case JSHandlers.text.rawValue:
            guard let data = message as? [String: Any], let event = data["event"] as? String else { return }
            switch event {
            case "onInitialized":
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(3)) {
                    loadData()
                }

            default:
                break
            }

        default:
            break
        }

        func loadData() {
            do {
                let data = try Data(contentsOf: self.url)
                let jsArrayData = try JSONSerialization.data(withJSONObject: [UInt8](data))
                guard let jsArrayString = String(data: jsArrayData, encoding: .utf8) else { return }
                self.webViewHandler.call(javascript: #"tester();"#)
                    .observe(on: MainScheduler.instance)
                    .subscribe(with: self, onFailure: { _, error in
                        DDLogError("HtmlEpubReaderViewController: call failed - \(error)")
                    })
                    .disposed(by: self.disposeBag)
            } catch let error {
                DDLogError("HtmlEpubReaderViewController: could not load file - \(error)")
            }
        }
    }

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
        self.webViewHandler = WebViewHandler(webView: webView, javascriptHandlers: JSHandlers.allCases.map({ $0.rawValue }))
        self.webViewHandler.receivedMessageHandler = { [weak self] handler, message in
            self?.process(handler: handler, message: message)
        }
    }

    private func setupNavigationBar() {
        let closeButton = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: nil, action: nil)
        closeButton.title = L10n.close
        closeButton.accessibilityLabel = L10n.close
        closeButton.rx.tap.subscribe(with: self, onNext: { `self`, _ in self.close() }).disposed(by: self.disposeBag)
        self.navigationItem.leftBarButtonItem = closeButton
    }
}
