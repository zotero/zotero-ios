//
//  NoteEditorViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 07/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import SafariServices
import UIKit
import WebKit

class NoteEditorViewController: UIViewController {
    let text: String
    let readOnly: Bool
    let saveAction: (String) -> Void

    private weak var webView: WKWebView!
    private weak var activityIndicator: UIActivityIndicatorView!

    private var htmlUrl: URL? {
        if self.readOnly {
            return Bundle.main.url(forResource: "note", withExtension: "html")
        } else {
            return Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "tinymce")
        }
    }

    init(text: String, readOnly: Bool, saveAction: @escaping (String) -> Void) {
        self.text = text
        self.readOnly = readOnly
        self.saveAction = saveAction
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = self.traitCollection.userInterfaceStyle == .light ? .white : .black
        self.setupNavbarItems()
        self.setupWebView()
        self.loadEditor()
    }

    // MARK: - Actions

    private func showWebView()  {
        UIView.animate(withDuration: 0.1, animations: {
            self.webView.alpha = 1
            self.activityIndicator.alpha =  0
        }) { _ in
            self.activityIndicator.stopAnimating()
            self.activityIndicator.isHidden = true
        }
    }

    private func loadEditor() {
        guard let url = self.htmlUrl,
              var data = try? String(contentsOf: url, encoding: .utf8) else { return }
        data = data.replacingOccurrences(of: "#initialnote", with: self.text)
        self.webView.loadHTMLString(data, baseURL: url)
    }

    @objc private func cancel() {
        self.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    @objc private func save() {
        self.webView.evaluateJavaScript("tinymce.get(\"tinymce\").getContent()") { [weak self] result, error in
            guard let `self` = self else { return }
            let newText = (result as? String) ?? ""
            self.saveAction(newText)
            self.presentingViewController?.dismiss(animated: true, completion: nil)
        }
    }
    
    // MARK: - Setups

    private func setupNavbarItems() {
        let cancelItem = UIBarButtonItem(title: L10n.cancel, style: .plain, target: self, action: #selector(NoteEditorViewController.cancel))
        self.navigationItem.leftBarButtonItem = cancelItem
        if !self.readOnly {
            let saveItem = UIBarButtonItem(title: L10n.save, style: .done, target: self, action: #selector(NoteEditorViewController.save))
            self.navigationItem.rightBarButtonItem = saveItem
        }
    }

    private func setupWebView() {
        let webView = WKWebView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.alpha = 0

        self.view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.leftAnchor.constraint(equalTo: self.view.leftAnchor),
            webView.rightAnchor.constraint(equalTo: self.view.rightAnchor),
            webView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor)
        ])

        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            activityIndicator.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
            activityIndicator.centerXAnchor.constraint(equalTo: self.view.centerXAnchor)
        ])

        activityIndicator.startAnimating()

        self.webView = webView
        self.activityIndicator = activityIndicator
    }

}

extension NoteEditorViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        // Allow initial load
        guard url.scheme == "http" || url.scheme == "https" else {
            decisionHandler(.allow)
            return
        }

        // Show other links in SFSafariView
        decisionHandler(.cancel)
        self.present(SFSafariViewController(url: url), animated: true, completion: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.showWebView()
    }
}
