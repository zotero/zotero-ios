//
//  NoteEditorViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 07/10/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

class NoteEditorViewController: UIViewController {
    let text: String
    let saveAction: (String) -> Void

    private weak var webView: WKWebView!

    init(text: String, saveAction: @escaping (String) -> Void) {
        self.text = text
        self.saveAction = saveAction
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupNavbarItems()
        self.setupWebView()
        self.loadEditor()
    }

    // MARK: - Actions

    private func loadEditor() {
        let html =
        """
        <!DOCTYPE html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1"/>
          <script src='https://cdn.tiny.cloud/1/no-api-key/tinymce/5/tinymce.min.js' referrerpolicy="origin"></script>
          <script>
          tinymce.init({
            selector: '#mytextarea',
            plugins: ['autoresize'],
            menubar: false,
            mobile: {
              theme: 'silver'
            }
          });
          </script>
        </head>

        <body width=320>
          <form method="post">
            <textarea id="mytextarea" name="mytextarea">\(self.text)</textarea>
          </form>
        </body>
        </html>
        """
        self.webView.loadHTMLString(html, baseURL: nil)
    }

    @objc private func cancel() {
        self.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    @objc private func save() {
        self.webView.evaluateJavaScript("tinymce.get(\"mytextarea\").getContent()") { [weak self] result, error in
            guard let `self` = self else { return }
            let newText = (result as? String) ?? ""
            self.saveAction(newText)
            self.presentingViewController?.dismiss(animated: true, completion: nil)
        }
    }
    
    // MARK: - Setups

    private func setupNavbarItems() {
        let cancelItem = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(NoteEditorViewController.cancel))
        self.navigationItem.leftBarButtonItem = cancelItem
        let saveItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(NoteEditorViewController.save))
        self.navigationItem.rightBarButtonItem = saveItem
    }

    private func setupWebView() {
        let webView = WKWebView()
        webView.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(webView)
        webView.leftAnchor.constraint(equalTo: self.view.leftAnchor).isActive = true
        webView.rightAnchor.constraint(equalTo: self.view.rightAnchor).isActive = true
        webView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor).isActive = true
        webView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor).isActive = true

        self.webView = webView
    }

}
