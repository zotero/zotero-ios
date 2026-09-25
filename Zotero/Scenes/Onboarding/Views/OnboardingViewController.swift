//
//  OnboardingViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 09/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import AuthenticationServices
import UIKit

import CocoaLumberjackSwift
import RxSwift

final class OnboardingViewController: UIViewController {
    private weak var spacerAboveScrollViewContent: UIView!
    private weak var spacerBelowScrollViewContent: UIView!
    private weak var spacerAboveScrollViewBottom: NSLayoutConstraint?
    private weak var scrollView: UIScrollView!
    private weak var signInButton: UIButton!
    private weak var learnMoreButton: UIButton!
    private weak var createAccountButton: UIButton!
    private weak var pageControl: UIPageControl!
    private weak var buttonStackView: UIStackView!
    private weak var bottomStackView: UIStackView!
    private weak var bottomStackViewWidth: NSLayoutConstraint!

    private let parentSize: CGSize
    private unowned let htmlConverter: HtmlAttributedStringConverter
    private let loginViewModel: ViewModel<LoginActionHandler>
    private let loginActivityIndicator: UIActivityIndicatorView
    private let createAccountActivityIndicator: UIActivityIndicatorView
    private let disposeBag: DisposeBag

    weak var coordinatorDelegate: AppOnboardingCoordinatorDelegate?
    private var presentedLoginURL: URL?
    private var authSession: ASWebAuthenticationSession?

    private let pageData: [(String, UIImage)] = [
        (L10n.Onboarding.access, Asset.Images.Onboarding.access.image),
        (L10n.Onboarding.annotate, Asset.Images.Onboarding.annotate.image),
        (L10n.Onboarding.share, Asset.Images.Onboarding.share.image),
        (L10n.Onboarding.sync, Asset.Images.Onboarding.sync.image)
    ]
    private var ignoreScrollDelegate: Bool

    // MARK: - Lifecycle

    init(size: CGSize, htmlConverter: HtmlAttributedStringConverter, loginViewModel: ViewModel<LoginActionHandler>) {
        self.parentSize = size
        self.htmlConverter = htmlConverter
        self.loginViewModel = loginViewModel
        self.ignoreScrollDelegate = false
        loginActivityIndicator = UIActivityIndicatorView(style: .medium)
        createAccountActivityIndicator = UIActivityIndicatorView(style: .medium)
        disposeBag = DisposeBag()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
        setupButtons()
        setupPages(with: pageData)
        setupPageControl(with: pageData)
        setupLayout(with: parentSize)
        updateLogin(state: loginViewModel.state)

        loginViewModel.stateObservable
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                self?.updateLogin(state: state)
            })
            .disposed(by: disposeBag)

        func setupUI() {
            view.backgroundColor = .systemBackground
            view.clearsContextBeforeDrawing = false

            let scrollView = UIScrollView()
            scrollView.bouncesZoom = false
            scrollView.clipsToBounds = true
            scrollView.delegate = self
            scrollView.isPagingEnabled = true
            scrollView.isMultipleTouchEnabled = true
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.showsVerticalScrollIndicator = false
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(scrollView)
            self.scrollView = scrollView

            let spacerAboveScrollViewContent = createSpacer(backgroundColor: .systemGreen)
            view.addSubview(spacerAboveScrollViewContent)
            self.spacerAboveScrollViewContent = spacerAboveScrollViewContent

            let spacerBelowScrollViewContent = createSpacer(backgroundColor: .systemPink)
            view.addSubview(spacerBelowScrollViewContent)
            self.spacerBelowScrollViewContent = spacerBelowScrollViewContent

            let signInButton = createButton(backgroundColor: Asset.Colors.zoteroBlueWithDarkMode.color, titleColor: .white)
            signInButton.addTarget(self, action: #selector(signIn), for: .touchUpInside)
            self.signInButton = signInButton

            let createAccountButton = createButton(backgroundColor: Asset.Colors.zoteroBlueWithDarkMode.color, titleColor: .white)
            createAccountButton.addTarget(self, action: #selector(createAccount), for: .touchUpInside)
            self.createAccountButton = createAccountButton

            let learnMoreButton = createButton(backgroundColor: nil, titleColor: Asset.Colors.zoteroBlueWithDarkMode.color)
            learnMoreButton.addTarget(self, action: #selector(showAbout), for: .touchUpInside)
            self.learnMoreButton = learnMoreButton

            let buttonStackView = UIStackView(arrangedSubviews: [signInButton, createAccountButton, learnMoreButton])
            buttonStackView.axis = .vertical
            self.buttonStackView = buttonStackView

            let pageControl = UIPageControl()
            pageControl.currentPageIndicatorTintColor = .systemGray
            pageControl.pageIndicatorTintColor = .systemGray4
            pageControl.addTarget(self, action: #selector(changePage(sender:)), for: .valueChanged)
            self.pageControl = pageControl

            let bottomStackView = UIStackView(arrangedSubviews: [pageControl, buttonStackView])
            bottomStackView.axis = .vertical
            bottomStackView.spacing = 17
            bottomStackView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(bottomStackView)
            self.bottomStackView = bottomStackView

            let bottomStackViewWidth = bottomStackView.widthAnchor.constraint(equalToConstant: 286)
            bottomStackViewWidth.priority = .defaultHigh
            self.bottomStackViewWidth = bottomStackViewWidth

            let bottomSpacer = createSpacer(backgroundColor: .systemIndigo)
            view.addSubview(bottomSpacer)

            let safeArea = view.safeAreaLayoutGuide
            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(equalTo: safeArea.topAnchor),
                scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                scrollView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),
                scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                spacerAboveScrollViewContent.topAnchor.constraint(equalTo: safeArea.topAnchor),
                spacerAboveScrollViewContent.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                spacerAboveScrollViewContent.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                spacerBelowScrollViewContent.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                spacerBelowScrollViewContent.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                spacerBelowScrollViewContent.heightAnchor.constraint(equalTo: spacerAboveScrollViewContent.heightAnchor),
                bottomStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                bottomStackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
                view.trailingAnchor.constraint(greaterThanOrEqualTo: bottomStackView.trailingAnchor, constant: 32),
                bottomStackView.topAnchor.constraint(equalTo: spacerBelowScrollViewContent.bottomAnchor, constant: -15),
                bottomSpacer.topAnchor.constraint(equalTo: bottomStackView.bottomAnchor),
                bottomSpacer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                bottomSpacer.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),
                bottomSpacer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                bottomSpacer.heightAnchor.constraint(equalTo: spacerAboveScrollViewContent.heightAnchor),
                bottomStackViewWidth
            ])

            func createSpacer(backgroundColor: UIColor) -> UIView {
                let view = UIView()
                view.backgroundColor = backgroundColor
                view.isHidden = true
                view.setContentHuggingPriority(.init(1), for: .vertical)
                view.setContentCompressionResistancePriority(.init(1), for: .horizontal)
                view.setContentCompressionResistancePriority(.init(1), for: .vertical)
                view.translatesAutoresizingMaskIntoConstraints = false
                return view
            }

            func createButton(backgroundColor: UIColor?, titleColor: UIColor) -> UIButton {
                let button = UIButton(type: .system)
                button.backgroundColor = backgroundColor
                button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
                button.setTitleColor(titleColor, for: .normal)
                button.titleLabel?.font = .preferredFont(forTextStyle: .body)
                button.titleLabel?.lineBreakMode = .byTruncatingMiddle
                button.tintColor = Asset.Colors.zoteroBlueWithDarkMode.color
                return button
            }
        }

        func setupButtons() {
            signInButton.layer.cornerRadius = 12
            signInButton.layer.masksToBounds = true
            signInButton.setTitle(L10n.Onboarding.signIn, for: .normal)
            createAccountButton.layer.cornerRadius = 12
            createAccountButton.layer.masksToBounds = true
            createAccountButton.setTitle(L10n.Onboarding.createAccount, for: .normal)
            learnMoreButton.setTitle(L10n.aboutZotero, for: .normal)
            setup(activityIndicator: loginActivityIndicator, in: signInButton)
            setup(activityIndicator: createAccountActivityIndicator, in: createAccountButton)

            func setup(activityIndicator: UIActivityIndicatorView, in button: UIButton) {
                activityIndicator.hidesWhenStopped = true
                activityIndicator.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(activityIndicator)
                NSLayoutConstraint.activate([
                    activityIndicator.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                    activityIndicator.centerYAnchor.constraint(equalTo: button.centerYAnchor)
                ])
            }
        }

        /// Setup pages so that the spacer in pages is the same height as spacers in this controller. Also set title with appropriate size and style.
        /// - parameter pageData: Title and image for each page.
        func setupPages(with pageData: [(String, UIImage)]) {
            // Create page views. Find page view with longest text
            var longestTextIdx = 0
            var pages: [OnboardingPageView] = []

            for (index, (text, image)) in pageData.enumerated() {
                let pageView = OnboardingPageView(frame: .zero)
                pageView.translatesAutoresizingMaskIntoConstraints = false
                pageView.set(string: text, image: image, size: parentSize, htmlConverter: htmlConverter)
                pages.append(pageView)

                if longestTextIdx != index && text.count > pageData[longestTextIdx].0.count {
                    longestTextIdx = index
                }
            }

            // Add all pages inside stack view which is assigned as content view for scroll view.
            let stackView = UIStackView(arrangedSubviews: pages)
            stackView.setContentCompressionResistancePriority(.required, for: .vertical)
            stackView.translatesAutoresizingMaskIntoConstraints = false

            scrollView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.addSubview(stackView)

            // Create constraints

            // Create constraints for stackView as content view.
            var constraints = [stackView.topAnchor.constraint(equalTo: scrollView.frameLayoutGuide.topAnchor),
                               stackView.bottomAnchor.constraint(equalTo: scrollView.frameLayoutGuide.bottomAnchor),
                               stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
                               stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor)]

            // Create spacer height constraint from page with biggest text to this controller's spacer so that the height between title and image
            // is the same as spacers in this controller.
            constraints.append(pages[longestTextIdx].spacer.heightAnchor.constraint(equalTo: spacerAboveScrollViewContent.heightAnchor))

            for (index, view) in pages.enumerated() {
                // Create constraints for pages so that their width is the same as scroll view.
                constraints.append(view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor))
                // Create height constraints between labels in pages so that the label height is the same in all pages and labels are vertically
                // centered to the biggest label.
                if index == longestTextIdx {
                    // Set content hugging of the longest label to required
                    view.textLabel.setContentHuggingPriority(.required, for: .vertical)
                    // Connect text to top content spacer
                    let textConstraint = view.textLabel.topAnchor.constraint(equalTo: spacerAboveScrollViewContent.bottomAnchor)
                    textConstraint.isActive = true
                    spacerAboveScrollViewBottom = textConstraint
                    // Connect image to bottom content spacer
                    spacerBelowScrollViewContent.topAnchor.constraint(equalTo: view.imageView.bottomAnchor, constant: -10).isActive = true
                } else {
                    let longestPage = pages[longestTextIdx]
                    constraints.append(view.textLabel.heightAnchor.constraint(equalTo: longestPage.textLabel.heightAnchor))
                    // Set content hugging of other labels to high, so that they don't try to compress the main label
                    view.textLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
                    // Connect text to longest text top, so that all pages start at the same height
                    view.textLabel.topAnchor.constraint(equalTo: longestPage.textLabel.topAnchor).isActive = true
                    // Connect image to longest image bottom, so that all pages end at the same height
                    view.imageView.bottomAnchor.constraint(equalTo: longestPage.imageView.bottomAnchor).isActive = true
                }
            }

            NSLayoutConstraint.activate(constraints)
        }

        func setupPageControl(with pageData: [(String, UIImage)]) {
            pageControl.numberOfPages = pageData.count
            pageControl.currentPage = 0
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        let page = scrollView.currentPage

        super.viewWillTransition(to: size, with: coordinator)

        guard let stackView = scrollView.subviews.last as? UIStackView,
              let pageViews = stackView.arrangedSubviews as? [OnboardingPageView],
              pageViews.count == pageData.count
        else { return }

        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            for (index, view) in pageViews.enumerated() {
                view.updateIfNeeded(to: size, string: pageData[index].0, htmlConverter: htmlConverter)
            }
            setupLayout(with: size)
            let scrollOffset = CGPoint(x: size.width * CGFloat(page), y: 0)
            scrollView.setContentOffset(scrollOffset, animated: false)
        }, completion: { [weak self] _ in
            // If iPhone Duo launches on the inner display,
            // UIKit continues ignoring this controller's orientation mask after moving to the outer display.
            // Force it to reevaluate the mask once the transition finishes.
            self?.setNeedsUpdateOfSupportedInterfaceOrientations()
        })
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.userInterfaceIdiom == .pad ? .all : [.portrait, .portraitUpsideDown]
    }

    // MARK: - Actions

    @objc private func changePage(sender: UIPageControl) {
        ignoreScrollDelegate = true
        let offset = CGPoint(x: scrollView.frame.width * CGFloat(sender.currentPage), y: 0)
        scrollView.setContentOffset(offset, animated: true)
    }

    @objc private func signIn() {
        loginViewModel.process(action: .login)
    }

    @objc private func createAccount() {
        loginViewModel.process(action: .createAccount)
    }

    @objc private func showAbout() {
        coordinatorDelegate?.showAbout()
    }

    // MARK: - Setups

    private func setupLayout(with size: CGSize) {
        let layout = OnboardingLayout.from(size: size)

        buttonStackView.spacing = layout.buttonSpacing
        bottomStackView.spacing = layout.bottomSpacing
        bottomStackViewWidth.constant = layout.bottomWidth

        // Align to xHeight of font
        let titleFont = layout.titleFont
        let fontOffset = titleFont.ascender - titleFont.xHeight
        spacerAboveScrollViewBottom?.constant = -fontOffset
    }

    private func updateLogin(state: LoginState) {
        applyLoginState(state)

        if let error = state.error {
            show(error: error)
        }

        if let loginURL = state.loginURL, presentedLoginURL != loginURL {
            presentedLoginURL = loginURL
            let authSession = ASWebAuthenticationSession(url: loginURL, callbackURLScheme: "zotero-ios", completionHandler: { [weak self] _, error in
                guard let self else { return }
                defer { self.authSession = nil }
                guard let error else { return }
                DDLogInfo("OnboardingViewController: login auth session completed with error - \(error)")
                switch (error as? ASWebAuthenticationSessionError)?.code {
                case .canceledLogin:
                    loginViewModel.process(action: .cancelLoginSessionIfNeeded)

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

        func applyLoginState(_ state: LoginState) {
            signInButton.isEnabled = !state.isLoading
            createAccountButton.isEnabled = !state.isLoading
            learnMoreButton.isEnabled = !state.isLoading

            if state.isLoading {
                switch state.requestKind {
                case .createAccount:
                    createAccountButton.setTitle(nil, for: .normal)
                    createAccountActivityIndicator.startAnimating()

                case .login, .none:
                    signInButton.setTitle(nil, for: .normal)
                    loginActivityIndicator.startAnimating()
                }
            } else {
                authSession?.cancel()
                authSession = nil
                loginActivityIndicator.stopAnimating()
                createAccountActivityIndicator.stopAnimating()
                signInButton.setTitle(L10n.Onboarding.signIn, for: .normal)
                createAccountButton.setTitle(L10n.Onboarding.createAccount, for: .normal)
                presentedLoginURL = nil
            }
        }

        func show(error: LoginError) {
            let controller = UIAlertController(title: L10n.error, message: error.localizedDescription, preferredStyle: .alert)
            controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
            authSession?.cancel()
            authSession = nil
            coordinatorDelegate?.presentAlert(controller)
        }
    }
}

extension OnboardingViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !ignoreScrollDelegate else { return }
        pageControl.currentPage = scrollView.currentPage
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        ignoreScrollDelegate = false
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        ignoreScrollDelegate = false
    }
}

extension OnboardingViewController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let window = view.window else {
            DDLogWarn("OnboardingViewController: could not return window as presentation anchor")
            return ASPresentationAnchor()
        }
        return window
    }
}

fileprivate extension UIScrollView {
    var currentPage: Int {
        return Int((contentOffset.x + (0.5 * frame.size.width)) / frame.width)
    }
}

extension OnboardingLayout {
    fileprivate var buttonSpacing: CGFloat {
        switch self {
        case .big, .medium:
            return 12

        case .small:
            return 8
        }
    }

    fileprivate var bottomSpacing: CGFloat {
        switch self {
        case .big, .medium:
            return 17

        case .small:
            return 9
        }
    }

    fileprivate var bottomWidth: CGFloat {
        switch self {
        case .big:
            return 380

        case .medium, .small:
            return 286
        }
    }
}
