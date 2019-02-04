//
//  OnboardingViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class OnboardingViewController: UIViewController {
    // Outlets
    @IBOutlet private weak var loginButton: UIButton!
    @IBOutlet private weak var registerButton: UIButton!
    // Constants
    private let apiClient: ApiClient
    private let secureStorage: SecureStorage
    private let dbStorage: DbStorage

    // MARK: - Lifecycle

    init(apiClient: ApiClient, secureStorage: SecureStorage, dbStorage: DbStorage) {
        self.apiClient = apiClient
        self.secureStorage = secureStorage
        self.dbStorage = dbStorage
        super.init(nibName: "OnboardingViewController", bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupStyle()
        self.setupLanguage()
    }

    // MARK: - Actions

    @IBAction private func performLogin() {
        let store = LoginStore(apiClient: self.apiClient, secureStorage: self.secureStorage, dbStorage: self.dbStorage)
        let controller = LoginViewController(store: store)
        self.show(controller: controller)
    }

    @IBAction private func performRegister() {
        let controller = RegisterViewController()
        self.show(controller: controller)
    }

    private func show(controller: UIViewController) {
        let navigationController = UINavigationController(rootViewController: controller)
        if UIDevice.current.userInterfaceIdiom == .pad {
            navigationController.modalPresentationStyle = .formSheet
            navigationController.modalTransitionStyle = .crossDissolve
        }
        self.present(navigationController, animated: true, completion: nil)
    }

    // MARK: - Setups

    private func setupLanguage() {
        self.loginButton.setTitle("Sign in", for: .normal)
        self.registerButton.setTitle("Create account", for: .normal)
    }

    private func setupStyle() {
        [self.loginButton, self.registerButton].forEach { button in
            button?.setTitleColor(UIColor.redButton, for: .normal)
            button?.layer.borderColor = UIColor.redButton.cgColor
            button?.layer.borderWidth = 2.0
            button?.layer.cornerRadius = 6.0
            button?.layer.masksToBounds = true
        }
    }
}
