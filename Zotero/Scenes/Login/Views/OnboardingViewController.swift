//
//  OnboardingViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 09/07/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SwiftUI

class OnboardingViewController: UIViewController {
    @IBOutlet private weak var spacer: UIView!
    @IBOutlet private weak var topSpacerBottomConstraint: NSLayoutConstraint!
    @IBOutlet private weak var scrollView: UIScrollView!
    @IBOutlet private weak var signInButton: UIButton!
    @IBOutlet private weak var createAccountButton: UIButton!
    @IBOutlet private weak var pageControl: UIPageControl!
    @IBOutlet private weak var buttonStackView: UIStackView!
    @IBOutlet private weak var bottomStackView: UIStackView!

    private static let smallSizeLimit: CGFloat = 768
    private unowned let htmlConverter: HtmlAttributedStringConverter
    private unowned let apiClient: ApiClient
    private unowned let sessionController: SessionController

    private var pageData: [(String, UIImage)] {
        return [(L10n.Onboarding.access, Asset.Images.Onboarding.access.image),
                (L10n.Onboarding.annotate, Asset.Images.Onboarding.annotate.image),
                (L10n.Onboarding.share, Asset.Images.Onboarding.share.image),
                (L10n.Onboarding.sync, Asset.Images.Onboarding.sync.image)]
    }
    private var ignoreScrollDelegate: Bool

    // MARK: - Lifecycle

    init(htmlConverter: HtmlAttributedStringConverter, apiClient: ApiClient, sessionController: SessionController) {
        self.htmlConverter = htmlConverter
        self.apiClient = apiClient
        self.sessionController = sessionController
        self.ignoreScrollDelegate = false
        super.init(nibName: "OnboardingViewController", bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationController?.delegate = self
        self.navigationController?.setNavigationBarHidden(true, animated: false)
        let pages = self.pageData
        self.setupButtons()
        self.setupPages(with: pages)
        self.setupPageControl(with: pages)
        self.setupLayout(with: (self.navigationController?.view.frame.size ?? CGSize()))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: true)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        let page = self.scrollView.currentPage

        super.viewWillTransition(to: size, with: coordinator)

        guard let stackView = self.scrollView.subviews.last as? UIStackView,
              let pageViews = stackView.arrangedSubviews as? [OnboardingPageView] else { return }

        let pageData = self.pageData

        guard pageViews.count == pageData.count else { return }

        coordinator.animate(alongsideTransition: { _ in
            for (index, view) in pageViews.enumerated() {
                view.updateIfNeeded(to: size, string: pageData[index].0, htmlConverter: self.htmlConverter)
            }
            self.setupLayout(with: size)
            let scrollOffset = CGPoint(x: size.width * CGFloat(page), y: 0)
            self.scrollView.setContentOffset(scrollOffset, animated: false)
        }, completion: nil)
    }

    // MARK: - Actions

    @IBAction private func changePage(sender: UIPageControl) {
        self.ignoreScrollDelegate = true
        let offset = CGPoint(x: self.scrollView.frame.width * CGFloat(sender.currentPage), y: 0)
        self.scrollView.setContentOffset(offset, animated: true)
    }

    @IBAction private func signIn() {
        let handler = LoginActionHandler(apiClient: self.apiClient, sessionController: self.sessionController)
        let state = LoginState(username: "", password: "", isLoading: false, error: nil)
        let view = LoginView().environmentObject(ViewModel(initialState: state, handler: handler))
        let controller = UIHostingController(rootView: view)
        self.navigationController?.pushViewController(controller, animated: true)
    }

    @IBAction private func createAccount() {
        let view = RegisterView()
        let controller = UIHostingController(rootView: view)
        self.navigationController?.pushViewController(controller, animated: true)
    }

    // MARK: - Setups

    private func setupPages(with pageData: [(String, UIImage)]) {
        let size = self.navigationController?.view.frame.size ?? CGSize()
        let pages = pageData.map({ text, image -> OnboardingPageView in
            return OnboardingPageView(string: text, image: image, size: size, htmlConverter: self.htmlConverter)
        })

        let stackView = UIStackView(arrangedSubviews: pages)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.addSubview(stackView)

        let pageConstraints = pages.map({ $0.spacer.heightAnchor.constraint(equalTo: self.spacer.heightAnchor) }) +
                              pages.map({ $0.widthAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.widthAnchor) })
        let stackViewConstraints = [stackView.topAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.topAnchor),
                                    stackView.bottomAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.bottomAnchor),
                                    stackView.leadingAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.leadingAnchor),
                                    stackView.trailingAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.trailingAnchor)]

        NSLayoutConstraint.activate(stackViewConstraints + pageConstraints)
    }

    private func setupButtons() {
        self.signInButton.layer.cornerRadius = 12
        self.signInButton.layer.masksToBounds = true
        self.signInButton.setTitle(L10n.Onboarding.signIn, for: .normal)
        self.createAccountButton.setTitle(L10n.Onboarding.createAccount, for: .normal)
    }

    private func setupPageControl(with pageData: [(String, UIImage)]) {
        self.pageControl.numberOfPages = pageData.count
        self.pageControl.currentPage = 0
    }

    private func setupLayout(with size: CGSize) {
        let isBig = min(size.width, size.height) >= OnboardingViewController.smallSizeLimit
        self.buttonStackView.spacing = isBig ? 12 : 8
        self.bottomStackView.spacing = isBig ? 17 : 9

        // Align to xHeight of font
        let titleFont = OnboardingPageView.font(for: size)
        let fontOffset = titleFont.ascender - titleFont.xHeight
        self.topSpacerBottomConstraint.constant = -fontOffset
    }
}

extension OnboardingViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !self.ignoreScrollDelegate else { return }
        self.pageControl.currentPage = scrollView.currentPage
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        self.ignoreScrollDelegate = false
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        self.ignoreScrollDelegate = false
    }
}

fileprivate extension UIScrollView {
    var currentPage: Int {
        return Int((self.contentOffset.x + (0.5 * self.frame.size.width)) / self.frame.width)
    }
}

extension OnboardingViewController: UINavigationControllerDelegate {
    func navigationControllerSupportedInterfaceOrientations(_ navigationController: UINavigationController) -> UIInterfaceOrientationMask {
        return UIDevice.current.userInterfaceIdiom == .pad ? .all : [.portrait, .portraitUpsideDown]
    }
}
