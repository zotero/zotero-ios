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

final class LoginViewController: UIViewController {
    @IBOutlet private weak var navbarHeight: NSLayoutConstraint!
    @IBOutlet private weak var closeButton: UIButton!
    @IBOutlet private weak var containerLeft: NSLayoutConstraint!
    @IBOutlet private weak var containerRight: NSLayoutConstraint!
    @IBOutlet private weak var containerTop: NSLayoutConstraint!
    @IBOutlet private weak var container: UIStackView!
    @IBOutlet private weak var loginActivityView: UIActivityIndicatorView!
    @IBOutlet private weak var topSeparator: UIView!
    @IBOutlet private weak var bottomSeparator: UIView!

    private let viewModel: ViewModel<LoginActionHandler>
    private let disposeBag: DisposeBag
    private var presentedLoginURL: URL?
    private var authSession: ASWebAuthenticationSession?

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

        viewModel.process(action: .login)

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
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.userInterfaceIdiom == .pad ? .all : [.portrait, .portraitUpsideDown]
    }

    // MARK: - UI State

    private func update(state: LoginState) {
        applyVisibility()
        applyLoadingState(for: state)

        if let error = state.error {
            show(error: error, dismissOnCancel: true)
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

        func applyVisibility() {
            closeButton.isHidden = true
        }

        func applyLoadingState(for state: LoginState) {
            if state.isLoading {
                loginActivityView.startAnimating()
            } else {
                loginActivityView.stopAnimating()
            }

            loginActivityView.isHidden = !state.isLoading
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

extension LoginViewController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let window = view.window else {
            DDLogWarn("LoginViewController: could return window as presentation anchor")
            return ASPresentationAnchor()
        }
        return window
    }
}
