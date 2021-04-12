//
//  LoginViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 10/08/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift
import RxCocoa

final class LoginViewController: UIViewController {
    @IBOutlet private weak var navbarHeight: NSLayoutConstraint!
    @IBOutlet private weak var closeButton: UIButton!
    @IBOutlet private weak var containerLeft: NSLayoutConstraint!
    @IBOutlet private weak var containerRight: NSLayoutConstraint!
    @IBOutlet private weak var containerTop: NSLayoutConstraint!
    @IBOutlet private weak var container: UIStackView!
    @IBOutlet private weak var usernameField: UITextField!
    @IBOutlet private weak var passwordField: UITextField!
    @IBOutlet private weak var loginButton: UIButton!
    @IBOutlet private weak var loginActivityView: UIActivityIndicatorView!
    @IBOutlet private weak var topSeparator: UIView!
    @IBOutlet private weak var forgotPasswordButton: UIButton!
    @IBOutlet private weak var bottomSeparator: UIView!

    private let viewModel: ViewModel<LoginActionHandler>
    private let disposeBag: DisposeBag

    weak var coordinatorDelegate: AppLoginCoordinatorDelegate?

    // MARK: - Lifecycle

    init(viewModel: ViewModel<LoginActionHandler>) {
        self.viewModel = viewModel
        self.disposeBag = DisposeBag()
        super.init(nibName: "LoginViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setup()

        self.usernameField.becomeFirstResponder()

        self.viewModel.stateObservable
                      .observeOn(MainScheduler.instance)
                      .subscribe(onNext: { [weak self] state in
                          self?.update(state: state)
                      })
                      .disposed(by: self.disposeBag)

        self.usernameField.rx
                          .text
                          .orEmpty
                          .observeOn(MainScheduler.instance)
                          .subscribe(onNext: { [weak self] text in
                              self?.viewModel.process(action: .setUsername(text))
                          })
                          .disposed(by: self.disposeBag)

        self.passwordField.rx
                          .text
                          .orEmpty
                          .observeOn(MainScheduler.instance)
                          .subscribe(onNext: { [weak self] text in
                              self?.viewModel.process(action: .setPassword(text))
                          })
                          .disposed(by: self.disposeBag)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.userInterfaceIdiom == .pad ? .all : [.portrait, .portraitUpsideDown]
    }

    // MARK: - UI State

    private func update(state: LoginState) {
        if state.isLoading {
            self.startLoadingIfNeeded()
        } else {
            self.stopLoadingIfNeeded()
        }

        if let error = state.error {
            switch error {
            case .invalidUsername, .loginFailed:
                self.usernameField.becomeFirstResponder()
            case .invalidPassword:
                self.passwordField.becomeFirstResponder()
            case .serverError, .unknown: break
            }
            self.show(error: error)
        }
    }

    private func show(error: LoginError) {
        let controller = UIAlertController(title: L10n.error, message: error.localizedDescription, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: nil))
        self.present(controller, animated: true, completion: nil)
    }

    private func startLoadingIfNeeded() {
        guard self.loginActivityView.isHidden else { return }
        self.loginActivityView.startAnimating()
        self.loginActivityView.isHidden = false
        self.loginButton.isHidden = true
    }

    private func stopLoadingIfNeeded() {
        guard !self.loginActivityView.isHidden else { return }
        self.loginActivityView.isHidden = true
        self.loginActivityView.stopAnimating()
        self.loginButton.isHidden = false
    }

    // MARK: - Actions

    @IBAction private func login() {
        self.viewModel.process(action: .login)
    }

    @IBAction private func showForgotPassword() {
        self.coordinatorDelegate?.showForgotPassword()
    }

    @IBAction private func dismiss() {
        self.dismiss(animated: true, completion: nil)
    }

    // MARK: - Helpers

    private var spacing: CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 35
        } else {
            return 24
        }
    }

    private var horizontalPadding: CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 20
        } else {
            return 16
        }
    }

    private var navigationBarHeight: CGFloat {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 56
        } else {
            return 44
        }
    }

    // MARK: - Setups

    private func setup() {
        // Layout
        let horizontalPadding = self.horizontalPadding
        let spacing = self.spacing
        let isIpad = UIDevice.current.userInterfaceIdiom == .pad

        self.navbarHeight.constant = self.navigationBarHeight
        self.closeButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: horizontalPadding, bottom: 0, right: horizontalPadding)
        self.containerLeft.constant = horizontalPadding
        self.containerRight.constant = horizontalPadding
        self.containerTop.constant = spacing
        self.container.spacing = spacing

        self.topSeparator.isHidden = !isIpad
        self.bottomSeparator.isHidden = isIpad

        // Localization
        self.usernameField.placeholder = L10n.Login.username
        self.passwordField.placeholder = L10n.Login.password
        self.loginButton.setTitle(L10n.Onboarding.signIn, for: .normal)
        self.forgotPasswordButton.setTitle(L10n.Login.forgotPassword, for: .normal)

        // Style
        self.loginButton.layer.masksToBounds = true
        self.loginButton.layer.cornerRadius = 12
    }
}

extension LoginViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == self.usernameField {
            self.passwordField.becomeFirstResponder()
        } else {
            self.viewModel.process(action: .login)
        }
        return true
    }
}
