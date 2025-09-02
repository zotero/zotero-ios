//
//  TextPreviewViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 29.04.2021.
//  Copyright © 2021 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class TextPreviewViewController: UIViewController {
    @IBOutlet private weak var textView: UITextView!

    private let text: String

    init(text: String, title: String) {
        self.text = text

        super.init(nibName: "TextPreviewViewController", bundle: nil)

        self.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupNavigationBar()
        self.textView.isEditable = false
        self.textView.text = self.text
    }

    private func setupNavigationBar() {
        let primaryAction = UIAction(title: L10n.close) { [weak self] _ in
            self?.navigationController?.presentingViewController?.dismiss(animated: true)
        }
        let closeItem: UIBarButtonItem
        if #available(iOS 26.0.0, *) {
            closeItem = UIBarButtonItem(systemItem: .close, primaryAction: primaryAction)
        } else {
            closeItem = UIBarButtonItem(primaryAction: primaryAction)
        }
        navigationItem.rightBarButtonItem = closeItem
    }
}
