//
//  RegisterViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class RegisterViewController: UIViewController {

    // MARK: - Lifecycle

    init() {
        super.init(nibName: "RegisterViewController", bundle: nil)
        self.preferredContentSize = CGSize(width: 400, height: 300)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupNavigationItems()
    }

    // MARK: - Actions

    @objc private func cancel() {
        self.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    // MARK: - Setups

    private func setupNavigationItems() {
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .plain, target: self,
                                                                action: #selector(RegisterViewController.cancel))
    }
}
