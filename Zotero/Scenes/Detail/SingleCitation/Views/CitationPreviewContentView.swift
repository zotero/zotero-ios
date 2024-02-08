//
//  CitationPreviewContentView.swift
//  Zotero
//
//  Created by Michal Rentka on 07.02.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

class CitationPreviewContentView: UIView {
    private static let verticalInset: CGFloat = 10

    private weak var webView: WKWebView!
    private weak var activityIndicator: UIActivityIndicatorView!
    private weak var heightConstraint: NSLayoutConstraint!

    init() {
        super.init(frame: .zero)

        backgroundColor = .systemGray5

        let webView = WKWebView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.scrollView.contentInset = UIEdgeInsets()
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        addSubview(webView)
        self.webView = webView

        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        addSubview(indicator)
        self.activityIndicator = indicator

        let heightConstraint = heightAnchor.constraint(equalToConstant: 40)
        self.heightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalInset),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            bottomAnchor.constraint(equalTo: webView.bottomAnchor, constant: Self.verticalInset),
            trailingAnchor.constraint(equalTo: webView.trailingAnchor, constant: 16),
            indicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            indicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            heightConstraint
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setup(preview: String, height: CGFloat) {
        heightConstraint.constant = height + (2 * Self.verticalInset)
        if !preview.isEmpty {
            webView.isHidden = false
            webView.loadHTMLString(injectStyle(toHtml: preview), baseURL: nil)
            activityIndicator.stopAnimating()
        } else {
            webView.isHidden = true
            activityIndicator.isHidden = false
            activityIndicator.startAnimating()
        }

        func injectStyle(toHtml htmlString: String) -> String {
            let style = "<style>body { padding: 0; margin: 0; font-family: -apple-system; background-color: transparent; }</style>"
            if let range = htmlString.range(of: "<head>") {
                var newString = htmlString
                newString.insert(contentsOf: style, at: range.upperBound)
                return newString
            } else if let range = htmlString.range(of: "<html>") {
                var newString = htmlString
                newString.insert(contentsOf: "<head>\(style)</head>", at: range.upperBound)
                return newString
            } else {
                return "<html><head>\(style)</head><body>\(htmlString)</body></html>"
            }
        }
    }
}
