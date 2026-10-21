//
//  WebViewChallengeViewController.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 13/10/26.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import WebKit

final class WebViewChallengeViewController: UIViewController {
    fileprivate let webView: WKWebView
    private let cancelled: () -> Void
    private let finished: () -> Void
    private var urlObservation: NSKeyValueObservation?
    private var didPresent = false
    private var isDismissing = false
    private var pendingDismissal: (() -> Void)?

    init(webView: WKWebView, cancelled: @escaping () -> Void, finished: @escaping () -> Void) {
        self.webView = webView
        self.cancelled = cancelled
        self.finished = finished
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        urlObservation = webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
            self?.title = webView.url?.host(percentEncoded: false)
        }
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.cancelled()
        })
        navigationItem.rightBarButtonItem = UIBarButtonItem(primaryAction: UIAction(title: L10n.Lookup.continue) { [weak self] action in
            (action.sender as? UIBarButtonItem)?.isEnabled = false
            self?.finished()
        })
        view.backgroundColor = .systemBackground
        setupWebView()
        preferredContentSize = CGSize(width: 600, height: 650)

        func setupWebView() {
            webView.removeFromSuperview()
            webView.isHidden = false
            webView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(webView)
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
                webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
            ])
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Check once UIKit has finished the transition, when a dismissed screen no longer has a presenting controller.
        DispatchQueue.main.async { [weak self] in
            self?.resolveIfDismissedExternally()
        }
    }

    private func resolveIfDismissedExternally() {
        guard navigationController?.presentingViewController == nil else { return }
        if let pendingDismissal {
            // The presentation was dismissed before it finished, so it will never complete the pending dismissal.
            self.pendingDismissal = nil
            pendingDismissal()
            return
        }
        guard !isDismissing else { return }
        // Dismissed outside the challenge flow. Resolve as the user would, so the pending request doesn't wait forever.
        isDismissing = true
        if didPresent {
            finished()
        } else {
            cancelled()
        }
    }

    fileprivate func presentationFinished(presented: () -> Void) {
        didPresent = true
        if let pendingDismissal {
            self.pendingDismissal = nil
            dismissChallenge(completion: pendingDismissal)
        } else {
            presented()
        }
    }

    fileprivate func dismissChallenge(completion: @escaping () -> Void) {
        isDismissing = true
        guard let navigationController, navigationController.presentingViewController != nil else {
            // Already dismissed outside the challenge flow; UIKit may not call the completion of a no-op dismissal.
            completion()
            return
        }
        guard didPresent else {
            // Clearance can finish while UIKit is still presenting this screen.
            pendingDismissal = completion
            return
        }
        navigationController.dismiss(animated: true, completion: completion)
    }
}

/// Keeps challenge presentation available after the lookup window has closed.
final class WebViewChallengePresentationController: WebViewChallengePresenter {
    private weak var rootViewController: UIViewController?
    private let isLookupOngoing: (@escaping (Bool) -> Void) -> Void
    private var challenges: [ObjectIdentifier: WebViewChallengeViewController] = [:]

    init(lookupViewController: UIViewController, isLookupOngoing: @escaping (@escaping (Bool) -> Void) -> Void) {
        rootViewController = lookupViewController.navigationController?.presentingViewController ?? lookupViewController.presentingViewController ?? lookupViewController
        self.isLookupOngoing = isLookupOngoing
    }

    func showBrowserChallenge(in webView: WKWebView, cancelled: @escaping () -> Void, finished: @escaping () -> Void, presented: @escaping () -> Void) {
        let controller = WebViewChallengeViewController(webView: webView, cancelled: cancelled, finished: finished)
        challenges[ObjectIdentifier(webView)] = controller
        present(controller, cancelled: cancelled, presented: presented)
    }

    private func present(_ controller: WebViewChallengeViewController, cancelled: @escaping () -> Void, presented: @escaping () -> Void) {
        isLookupOngoing { [weak self, weak controller] ongoing in
            guard let self, let controller, challenges[ObjectIdentifier(controller.webView)] === controller else { return }
            guard ongoing, let rootViewController else {
                cancelled()
                return
            }
            let presenter = rootViewController.topController
            if let transition = presenter.transitionCoordinator ?? rootViewController.transitionCoordinator {
                let waiting = transition.animate(alongsideTransition: nil) { [weak self, weak controller] _ in
                    // Let UIKit finish updating the presented-controller hierarchy first.
                    DispatchQueue.main.async { [weak self, weak controller] in
                        guard let self, let controller else { return }
                        present(controller, cancelled: cancelled, presented: presented)
                    }
                }
                if waiting { return }
            }
            guard presenter.viewIfLoaded?.window != nil,
                  !presenter.isBeingDismissed,
                  !presenter.isBeingPresented,
                  presenter.presentedViewController == nil else {
                cancelled()
                return
            }
            let navigationController = UINavigationController(rootViewController: controller)
            navigationController.modalPresentationStyle = .formSheet
            navigationController.isModalInPresentation = true
            navigationController.preferredContentSize = CGSize(width: 600, height: 650)
            presenter.present(navigationController, animated: true) {
                controller.presentationFinished(presented: presented)
            }
        }
    }

    func dismissBrowserChallenge(in webView: WKWebView, completion: @escaping () -> Void) {
        guard let controller = challenges.removeValue(forKey: ObjectIdentifier(webView)) else {
            completion()
            return
        }
        // A pending presentation has no navigation controller yet. Removing it also invalidates deferred callbacks.
        guard controller.navigationController != nil else {
            completion()
            return
        }
        controller.dismissChallenge(completion: completion)
    }
}
