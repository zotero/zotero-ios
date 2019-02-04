//
//  LoginViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class LoginViewController: UIViewController {
    // Outlets
    @IBOutlet private weak var usernameField: UITextField!
    @IBOutlet private weak var passwordField: UITextField!
    @IBOutlet private weak var loginButton: UIButton!
    @IBOutlet private weak var activityIndicator: UIActivityIndicatorView!
    // Constants
    private let store: LoginStore
    // Variables
    private var storeToken: StoreSubscriptionToken?

    // MARK: - Lifecycle

    init(store: LoginStore) {
        self.store = store
        super.init(nibName: "LoginViewController", bundle: nil)
        self.preferredContentSize = CGSize(width: 400, height: 200)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.setupNavigationItems()
        self.setupStyle()

        self.storeToken = self.store.subscribe { [weak self] state in
            self?.update(to: state)
        }
    }

    // MARK: - Actions

    private func update(to state: LoginState) {
        switch state {
        case .input:
            self.activityIndicator.stopAnimating()
            self.activityIndicator.isHidden = true
            self.loginButton.isHidden = false
        case .loading:
            self.activityIndicator.startAnimating()
            self.activityIndicator.isHidden = false
            self.loginButton.isHidden = true
        case .error(let error):
            self.showAlert(for: error) { [weak self] in
                self?.store.handle(action: .hideError)

                if let error = error as? LoginError {
                    switch error {
                    case .invalidPassword:
                        self?.passwordField.becomeFirstResponder()
                    case .invalidUsername:
                        self?.usernameField.becomeFirstResponder()
                    }
                }
            }
        }
    }

    @IBAction private func login() {
        guard let username = self.usernameField.text,
              let password = self.passwordField.text else {
            return
        }
        self.store.handle(action: .login(username: username, password: password))
    }

    @objc private func cancel() {
        self.presentingViewController?.dismiss(animated: true, completion: nil)
    }

    // MARK: - Setups

    private func setupNavigationItems() {
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .plain, target: self,
                                                                action: #selector(LoginViewController.cancel))
    }

    private func setupStyle() {
        self.loginButton.setTitleColor(UIColor.redButton, for: .normal)
        self.loginButton.layer.borderColor = UIColor.redButton.cgColor
        self.loginButton.layer.borderWidth = 2.0
        self.loginButton.layer.cornerRadius = 6.0
        self.loginButton.layer.masksToBounds = true
    }
}
