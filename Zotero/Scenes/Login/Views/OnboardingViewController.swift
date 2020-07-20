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
    @IBOutlet private weak var spacerAboveScrollViewContent: UIView!
    @IBOutlet private weak var spacerBelowScrollViewContent: UIView!
    private weak var spacerAboveScrollViewBottom: NSLayoutConstraint?
    @IBOutlet private weak var scrollView: UIScrollView!
    @IBOutlet private weak var signInButton: UIButton!
    @IBOutlet private weak var createAccountButton: UIButton!
    @IBOutlet private weak var pageControl: UIPageControl!
    @IBOutlet private weak var buttonStackView: UIStackView!
    @IBOutlet private weak var bottomStackView: UIStackView!
    @IBOutlet private weak var bottomStackViewWidth: NSLayoutConstraint!

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

    /// Setup pages so that the spacer in pages is the same height as spacers in this controller. Also set title with appropriate size and style.
    /// - parameter pageData: Title and image for each page.
    private func setupPages(with pageData: [(String, UIImage)]) {
        let size = self.navigationController?.view.frame.size ?? CGSize()

        // Create page views. Find page view with longest text
        var longestTextIdx = 0
        var pages: [OnboardingPageView] = []

        for (index, (text, image)) in pageData.enumerated() {
            let pageView = UINib(nibName: "OnboardingPageView", bundle: nil).instantiate(withOwner: nil, options: nil).first as! OnboardingPageView
            pageView.translatesAutoresizingMaskIntoConstraints = false
            pageView.set(string: text, image: image, size: size, htmlConverter: self.htmlConverter)
            pages.append(pageView)

            if longestTextIdx != index && text.count > pageData[longestTextIdx].0.count {
                longestTextIdx = index
            }
        }

        // Add all pages inside stack view which is assigned as content view for scroll view.
        let stackView = UIStackView(arrangedSubviews: pages)
        stackView.setContentCompressionResistancePriority(.required, for: .vertical)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.addSubview(stackView)

        // Create constraints

        // Create constraints for stackView as content view.
        var constraints = [stackView.topAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.topAnchor),
                           stackView.bottomAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.bottomAnchor),
                           stackView.leadingAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.leadingAnchor),
                           stackView.trailingAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.trailingAnchor)]

        // Create spacer height constraint from page with biggest text to this controller's spacer so that the height between title and image
        // is the same as spacers in this controller.
        constraints.append(pages[longestTextIdx].spacer.heightAnchor.constraint(equalTo: self.spacer.heightAnchor))

        for (index, view) in pages.enumerated() {
            // Create constraints for pages so that their width is the same as scroll view.
            constraints.append(view.widthAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.widthAnchor))
            // Create height constraints between labels in pages so that the label height is the same in all pages and labels are vertically
            // centered to the biggest label.
            if index == longestTextIdx {
                // Set content hugging of the longest label to required
                view.textLabel.setContentHuggingPriority(.required, for: .vertical)
                // Connect text to top content spacer
                let textConstraint = view.textLabel.topAnchor.constraint(equalTo: self.spacerAboveScrollViewContent.bottomAnchor)
                textConstraint.isActive = true
                self.spacerAboveScrollViewBottom = textConstraint
                // Connect image to bottom content spacer
                self.spacerBelowScrollViewContent.topAnchor.constraint(equalTo: view.imageView.bottomAnchor, constant: -10).isActive = true
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
        let layout = OnboardingLayout.from(size: size)

        self.buttonStackView.spacing = layout.buttonSpacing
        self.bottomStackView.spacing = layout.bottomSpacing
        self.bottomStackViewWidth.constant = layout.bottomWidth

        // Align to xHeight of font
        let titleFont = layout.titleFont
        let fontOffset = titleFont.ascender - titleFont.xHeight
        self.spacerAboveScrollViewBottom?.constant = -fontOffset
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

extension OnboardingLayout {
    fileprivate var buttonSpacing: CGFloat {
        switch self {
        case .big, .medium: return 12
        case .small: return 8
        }
    }

    fileprivate var bottomSpacing: CGFloat {
        switch self {
        case .big, .medium: return 17
        case .small: return 9
        }
    }

    fileprivate var bottomWidth: CGFloat {
        switch self {
        case .big: return 380
        case .medium, .small: return 286
        }
    }
}
