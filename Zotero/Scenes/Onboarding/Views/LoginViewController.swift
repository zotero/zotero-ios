//
//  LoginViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 10/08/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import AuthenticationServices
import UIKit

import CocoaLumberjackSwift
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
    private var presentedLoginURL: URL?
    private var authSession: ASWebAuthenticationSession?

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
        setup()
        update(state: viewModel.state)

        viewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                self?.update(state: state)
            })
            .disposed(by: disposeBag)

        usernameField.rx
            .text
            .orEmpty
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] text in
                self?.viewModel.process(action: .setUsername(text))
            })
            .disposed(by: disposeBag)

        passwordField.rx
            .text
            .orEmpty
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] text in
                self?.viewModel.process(action: .setPassword(text))
            })
            .disposed(by: disposeBag)

        switch viewModel.state.kind {
        case .password:
            usernameField.becomeFirstResponder()

        case .session:
            viewModel.process(action: .login)
        }

        func setup() {
            // Layout
            let isIpad = UIDevice.current.userInterfaceIdiom == .pad
            var closeConfiguration = UIButton.Configuration.plain()
            closeConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: horizontalPadding, bottom: 0, trailing: horizontalPadding)
            closeButton.configuration = closeConfiguration
            navbarHeight.constant = navigationBarHeight
            containerLeft.constant = horizontalPadding
            containerRight.constant = horizontalPadding
            containerTop.constant = spacing
            container.spacing = spacing
            topSeparator.isHidden = !isIpad
            bottomSeparator.isHidden = isIpad
            // Localization
            usernameField.placeholder = L10n.Login.username
            passwordField.placeholder = L10n.Login.password
            loginButton.setTitle(L10n.Onboarding.signIn, for: .normal)
            forgotPasswordButton.setTitle(L10n.Login.forgotPassword, for: .normal)
            // Style
            loginButton.layer.masksToBounds = true
            loginButton.layer.cornerRadius = 12
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.userInterfaceIdiom == .pad ? .all : [.portrait, .portraitUpsideDown]
    }

    // MARK: - UI State

    private func update(state: LoginState) {
        apply(kind: state.kind)
        applyLoadingState(for: state)

        if let error = state.error {
            switch error {
            case .invalidUsername, .loginFailed:
                usernameField.becomeFirstResponder()

            case .invalidPassword:
                passwordField.becomeFirstResponder()

            case .serverError, .sessionTimedOut, .unknown:
                break
            }

            show(error: error, dismissOnCancel: state.kind == .session)
        }

        if state.shouldDismiss {
            dismiss()
            return
        }

        if let loginURL = state.loginURL, presentedLoginURL != loginURL {
            presentedLoginURL = loginURL
            let authSession = ASWebAuthenticationSession(url: loginURL, callbackURLScheme: "zotero-ios", completionHandler: { [weak self] _, error in
                guard let self else { return }
                defer { self.authSession = nil }
                guard let error else { return }
                DDLogInfo("LoginViewController: login auth session completed with error - \(error)")
                switch (error as? ASWebAuthenticationSessionError)?.code {
                case .canceledLogin:
                    dismiss()

                case .presentationContextInvalid, .presentationContextNotProvided, .none:
                    break

                default:
                    break
                }
            })
            authSession.prefersEphemeralWebBrowserSession = true
            authSession.presentationContextProvider = self
            authSession.start()
            self.authSession = authSession
        }

        func apply(kind: LoginState.Kind) {
            let isPasswordLogin = (kind == .password)
            closeButton.isHidden = !isPasswordLogin
            usernameField.superview?.superview?.isHidden = !isPasswordLogin
            forgotPasswordButton.isHidden = !isPasswordLogin
        }

        func applyLoadingState(for state: LoginState) {
            if state.isLoading {
                loginActivityView.startAnimating()
            } else {
                loginActivityView.stopAnimating()
            }

            loginActivityView.isHidden = !state.isLoading
            loginButton.isHidden = (state.kind == .session) || state.isLoading
        }
    }

    private func show(error: LoginError, dismissOnCancel: Bool) {
        let controller = UIAlertController(title: L10n.error, message: error.localizedDescription, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: { [weak self] _ in
            guard dismissOnCancel else { return }
            self?.dismiss()
        }))
        if presentedViewController != nil {
            dismiss(animated: true) { [weak self] in
                self?.present(controller, animated: true)
            }
        } else {
            present(controller, animated: true)
        }
    }

    // MARK: - Actions

    @IBAction private func login() {
        viewModel.process(action: .login)
    }

    @IBAction private func showForgotPassword() {
        coordinatorDelegate?.showForgotPassword()
    }

    @IBAction private func dismiss() {
        viewModel.process(action: .cancelLoginSessionIfNeeded)
        authSession?.cancel()
        authSession = nil
        dismiss(animated: true, completion: nil)
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
}

extension LoginViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard viewModel.state.kind == .password else { return true }

        if textField == usernameField {
            passwordField.becomeFirstResponder()
        } else {
            viewModel.process(action: .login)
        }
        return true
    }
}

extension LoginViewController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let window = view.window else {
            DDLogWarn("LoginViewController: could return window as presentation anchor")
            return ASPresentationAnchor()
        }
        return window
    }
}
