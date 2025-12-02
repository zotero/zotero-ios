//
//  IntraDocumentNavigationButtonsHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 19.02.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

protocol IntraDocumentNavigationButtonsHandlerDelegate: AnyObject {
    var isCompactWidth: Bool { get }
    var sidebarView: UIView? { get }
}

enum PageChange {
    case manual
    case link
    case programmatic
}

final class IntraDocumentNavigationButtonsHandler {
    let back: () -> Void
    let forward: () -> Void
    private unowned let delegate: IntraDocumentNavigationButtonsHandlerDelegate

    lazy var backButton: UIButton = {
        return createButton(title: L10n.back, imageSystemName: "chevron.left", action: UIAction(handler: { [weak self] _ in self?.back() }))
    }()
    lazy var forwardButton: UIButton = {
        return createButton(title: L10n.forward, imageSystemName: "chevron.right", action: UIAction(handler: { [weak self] _ in self?.forward() }))
    }()
    var showsBackButton: Bool {
        backButton.isHidden == false
    }
    var showsForwardButton: Bool {
        forwardButton.isHidden == false
    }
    private(set) var hasBackActions: Bool = false
    private(set) var hasForwardActions: Bool = false
    var interfaceIsVisible: Bool = true {
        didSet {
            updateVisibility()
        }
    }
    private var backDisappearingTimer: BackgroundTimer?
    private var forwardDisappearingTimer: BackgroundTimer?

    init(back: @escaping () -> Void, forward: @escaping () -> Void, delegate: IntraDocumentNavigationButtonsHandlerDelegate) {
        self.back = back
        self.forward = forward
        self.delegate = delegate
    }

    func set(hasBackActions: Bool, hasForwardActions: Bool) {
        self.hasBackActions = hasBackActions
        self.hasForwardActions = hasForwardActions
        updateVisibility()
    }

    func backActionExecuted() {
        resetBothDisappearingTimers()
        updateVisibility()
    }

    func forwardActionExecuted() {
        resetBothDisappearingTimers()
        updateVisibility()
    }

    func pageChanged(_ pageChange: PageChange) {
        updateVisibility(pageChange: pageChange)
    }

    static private let disappearingDelay: DispatchTimeInterval = .milliseconds(3000)
    private func updateVisibility(pageChange: PageChange? = nil) {
        defer {
            if let sidebarView = delegate.sidebarView {
                backButton.superview?.insertSubview(backButton, belowSubview: sidebarView)
                backButton.superview?.insertSubview(forwardButton, belowSubview: sidebarView)
            } else {
                backButton.superview?.bringSubviewToFront(backButton)
                forwardButton.superview?.bringSubviewToFront(forwardButton)
            }
        }
        if interfaceIsVisible || (!hasBackActions && !hasForwardActions) {
            resetBothDisappearingTimers()
            // Update the buttons.
            backButton.isHidden = !hasBackActions
            forwardButton.isHidden = !hasForwardActions
            return
        }
        if hasBackActions {
            // Interface is not visible and there are back actions.
            switch pageChange {
            case .manual:
                // A manual page change by scrolling triggered this update. Start a disappearing timer, if one is not already running.
                backButton.isHidden = false
                startBackDisappearingTimerIfNeeded()

            case .none, .link, .programmatic:
                // Another change triggered this update. Reset timer and show button.
                resetBackDisappearingTimer()
                backButton.isHidden = false
            }
        }
        if hasForwardActions {
            // Interface is not visible and there are forward actions.
            switch pageChange {
            case .manual:
                // A manual page change by scrolling triggered this update. Start a disappearing timer, if one is not already running.
                forwardButton.isHidden = false
                startForwardDisappearingTimerIfNeeded()

            case .none, .link, .programmatic:
                // Another change triggered this update. Reset timer, show button, and start timer again.
                resetForwardDisappearingTimer()
                forwardButton.isHidden = false
                startForwardDisappearingTimerIfNeeded()
            }
        }

        func startBackDisappearingTimerIfNeeded() {
            guard backDisappearingTimer == nil else { return }
            backDisappearingTimer = BackgroundTimer(timeInterval: Self.disappearingDelay, queue: .main)
            backDisappearingTimer?.eventHandler = { [weak self] in
                guard let self else { return }
                backButton.isHidden = true
                backDisappearingTimer = nil
            }
            backDisappearingTimer?.resume()
        }

        func startForwardDisappearingTimerIfNeeded() {
            guard forwardDisappearingTimer == nil else { return }
            forwardDisappearingTimer = BackgroundTimer(timeInterval: Self.disappearingDelay, queue: .main)
            forwardDisappearingTimer?.eventHandler = { [weak self] in
                guard let self else { return }
                forwardButton.isHidden = true
                forwardDisappearingTimer = nil
            }
            forwardDisappearingTimer?.resume()
        }
    }

    func containerViewWillTransitionToNewSize() {
        backButton.setNeedsUpdateConfiguration()
        forwardButton.setNeedsUpdateConfiguration()
    }

    private func resetBackDisappearingTimer() {
        backDisappearingTimer?.suspend()
        backDisappearingTimer = nil
    }

    private func resetForwardDisappearingTimer() {
        forwardDisappearingTimer?.suspend()
        forwardDisappearingTimer = nil
    }

    private func resetBothDisappearingTimers() {
        resetBackDisappearingTimer()
        resetForwardDisappearingTimer()
    }

    private func createButton(title: String, imageSystemName: String, action: UIAction) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: imageSystemName, withConfiguration: UIImage.SymbolConfiguration(scale: .small))
        configuration.baseForegroundColor = Asset.Colors.zoteroBlueWithDarkMode.color
        configuration.background.backgroundColor = Asset.Colors.navbarBackground.color
        configuration.imagePadding = 8
        let button = UIButton(configuration: configuration)
        button.configurationUpdateHandler = { [weak self] button in
            guard let self else { return }
            var configuration = button.configuration
            configuration?.title = delegate.isCompactWidth ? nil : title
            button.configuration = configuration
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.defaultHigh, for: .vertical)
        button.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        button.addAction(action, for: .touchUpInside)
        return button
    }
}
