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
    @IBOutlet private weak var scrollView: UIScrollView!
    @IBOutlet private weak var signInButton: UIButton!
    @IBOutlet private weak var createAccountButton: UIButton!
    @IBOutlet private weak var pageControl: UIPageControl!

    private static let titleFont: UIFont = .systemFont(ofSize: 20)
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

        self.navigationController?.setNavigationBarHidden(true, animated: false)
        let pages = self.pageData
        self.setupButtons()
        self.setupPages(with: pages)
        self.setupPageControl(with: pages)
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
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 1.5
        let kern = OnboardingViewController.titleFont.pointSize * 0.025

        let pages = pageData.map({ text, image -> OnboardingPageView in
            let attributedString = self.htmlConverter.convert(text: text,
                                                              baseFont: OnboardingViewController.titleFont,
                                                              baseAttributes: [.paragraphStyle: paragraphStyle, .kern: kern])
            return OnboardingPageView(attributedString: attributedString, image: image)
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
}

extension OnboardingViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !self.ignoreScrollDelegate else { return }
        let page = Int((scrollView.contentOffset.x + (0.5 * scrollView.frame.size.width)) / scrollView.frame.width)
        self.pageControl.currentPage = page
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        self.ignoreScrollDelegate = false
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        self.ignoreScrollDelegate = false
    }
}
