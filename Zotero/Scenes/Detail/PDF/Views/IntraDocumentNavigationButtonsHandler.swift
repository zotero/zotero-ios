//
//  IntraDocumentNavigationButtonsHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 19.02.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

protocol IntraDocumentNavigationButtonsHandlerDelegate: AnyObject {
    var sidebarView: UIView? { get }
}

enum PageChange {
    case manual
    case link
    case programmatic
}

final class IntraDocumentNavigationButtonsHandler {
    private enum Kind {
        case back
        case forward
    }

    /// Horizontal distance of the buttons from the document's safe area edges.
    private static let horizontalInset: CGFloat = 20
    /// Distance of the buttons' bottom from the document's bottom.
    private static let bottomInset: CGFloat = 40

    let back: () -> Void
    let forward: () -> Void
    private unowned let delegate: IntraDocumentNavigationButtonsHandlerDelegate
    /// View the buttons are added to.
    private weak var containerView: UIView?
    /// View the buttons are laid out against. Must be a subview of `containerView`.
    private weak var documentView: UIView?

    // Buttons are created the first time they need to be shown.
    private(set) var backButton: UIButton?
    private(set) var forwardButton: UIButton?
    var showsBackButton: Bool {
        backButton?.isHidden == false
    }
    var showsForwardButton: Bool {
        forwardButton?.isHidden == false
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

    init(
        containerView: UIView,
        documentView: UIView,
        back: @escaping () -> Void,
        forward: @escaping () -> Void,
        delegate: IntraDocumentNavigationButtonsHandlerDelegate
    ) {
        self.containerView = containerView
        self.documentView = documentView
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

    func updateButtonsZPosition() {
        let sidebarView = delegate.sidebarView
        for button in [backButton, forwardButton] {
            guard let button, let superview = button.superview else { continue }
            if let sidebarView {
                superview.insertSubview(button, belowSubview: sidebarView)
            } else {
                superview.bringSubviewToFront(button)
            }
        }
    }

    static private let disappearingDelay: DispatchTimeInterval = .milliseconds(3000)
    private func updateVisibility(pageChange: PageChange? = nil) {
        defer {
            updateButtonsZPosition()
        }
        if interfaceIsVisible || (!hasBackActions && !hasForwardActions) {
            resetBothDisappearingTimers()
            // Update the buttons.
            setButton(.back, hidden: !hasBackActions)
            setButton(.forward, hidden: !hasForwardActions)
            return
        }
        if hasBackActions {
            // Interface is not visible and there are back actions.
            switch pageChange {
            case .manual:
                // A manual page change by scrolling triggered this update. Start a disappearing timer, if one is not already running.
                setButton(.back, hidden: false)
                startBackDisappearingTimerIfNeeded()

            case .none, .link, .programmatic:
                // Another change triggered this update. Reset timer and show button.
                resetBackDisappearingTimer()
                setButton(.back, hidden: false)
            }
        }
        if hasForwardActions {
            // Interface is not visible and there are forward actions.
            switch pageChange {
            case .manual:
                // A manual page change by scrolling triggered this update. Start a disappearing timer, if one is not already running.
                setButton(.forward, hidden: false)
                startForwardDisappearingTimerIfNeeded()

            case .none, .link, .programmatic:
                // Another change triggered this update. Reset timer, show button, and start timer again.
                resetForwardDisappearingTimer()
                setButton(.forward, hidden: false)
                startForwardDisappearingTimerIfNeeded()
            }
        }

        func startBackDisappearingTimerIfNeeded() {
            guard backDisappearingTimer == nil else { return }
            backDisappearingTimer = BackgroundTimer(timeInterval: Self.disappearingDelay, queue: .main)
            backDisappearingTimer?.eventHandler = { [weak self] in
                guard let self else { return }
                setButton(.back, hidden: true)
                backDisappearingTimer = nil
            }
            backDisappearingTimer?.resume()
        }

        func startForwardDisappearingTimerIfNeeded() {
            guard forwardDisappearingTimer == nil else { return }
            forwardDisappearingTimer = BackgroundTimer(timeInterval: Self.disappearingDelay, queue: .main)
            forwardDisappearingTimer?.eventHandler = { [weak self] in
                guard let self else { return }
                setButton(.forward, hidden: true)
                forwardDisappearingTimer = nil
            }
            forwardDisappearingTimer?.resume()
        }
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

    /// Shows or hides a button, creating it the first time it is shown.
    private func setButton(_ kind: Kind, hidden: Bool) {
        switch kind {
        case .back:
            if !hidden, backButton == nil {
                backButton = createButton(kind: .back)
            }
            backButton?.isHidden = hidden

        case .forward:
            if !hidden, forwardButton == nil {
                forwardButton = createButton(kind: .forward)
            }
            forwardButton?.isHidden = hidden
        }
    }

    private func createButton(kind: Kind) -> UIButton? {
        guard let containerView, let documentView else { return nil }
        let title: String
        let imageSystemName: String
        let action: UIAction
        switch kind {
        case .back:
            title = L10n.back
            imageSystemName = "chevron.left"
            action = UIAction(handler: { [weak self] _ in self?.back() })

        case .forward:
            title = L10n.forward
            imageSystemName = "chevron.right"
            action = UIAction(handler: { [weak self] _ in self?.forward() })
        }

        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: imageSystemName, withConfiguration: UIImage.SymbolConfiguration(scale: .small))
        configuration.baseForegroundColor = Asset.Colors.zoteroBlueWithDarkMode.color
        configuration.background.backgroundColor = Asset.Colors.navbarBackground.color
        configuration.imagePadding = 8
        let button = UIButton(configuration: configuration)
        button.configurationUpdateHandler = { button in
            let hasCompactWidth = button.traitCollection.horizontalSizeClass == .compact
            var configuration = button.configuration
            configuration?.title = hasCompactWidth ? nil : title
            button.configuration = configuration
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.defaultHigh, for: .vertical)
        button.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        button.addAction(action, for: .touchUpInside)

        containerView.addSubview(button)
        let horizontalConstraint: NSLayoutConstraint
        switch kind {
        case .back:
            horizontalConstraint = button.leadingAnchor.constraint(equalTo: documentView.safeAreaLayoutGuide.leadingAnchor, constant: Self.horizontalInset)

        case .forward:
            horizontalConstraint = documentView.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: Self.horizontalInset)
        }
        NSLayoutConstraint.activate([
            horizontalConstraint,
            documentView.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: Self.bottomInset)
        ])

        // Lay out the new button right away, so that its frame is valid for callers reading it (e.g. the annotation toolbar's available size).
        UIView.performWithoutAnimation {
            containerView.layoutIfNeeded()
        }
        return button
    }
}
