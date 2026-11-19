//
//  IntraDocumentNavigationButtonsHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 19.02.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import PSPDFKitUI

protocol IntraDocumentNavigationButtonsHandlerDelegate: AnyObject {
    var sidebarView: UIView? { get }
}

enum PageChange {
    case manual
    case link
    case programmatic
}

@MainActor
final class IntraDocumentNavigationButtonsHandler {
    private enum Kind {
        case back
        case forward

        var title: String {
            switch self {
            case .back:
                return L10n.back

            case .forward:
                return L10n.forward
            }
        }

        var imageSystemName: String {
            switch self {
            case .back:
                return "chevron.left"

            case .forward:
                return "chevron.right"
            }
        }
    }

    private struct MeasuredWidthKey: Hashable {
        let kind: Kind
        let showsTitle: Bool
        let contentSizeCategory: UIContentSizeCategory
    }

    /// Horizontal distance of the buttons from the document's safe area edges.
    private static let horizontalInset: CGFloat = 20
    /// Distance of the buttons' bottom from the document's bottom.
    private static let bottomInset: CGFloat = 40
    /// Horizontal margin PSPDFKit keeps, on each side, between the scrubber bar's frame and its floating content. The floating content is at most
    /// as wide as the scrubber bar minus 32 (`-[PSPDFScrubberBar maximumSizeForScrubberBar:]`, which isn't public, so this is assumed).
    private static let floatingScrubberBarContentMargin: CGFloat = 16

    let back: () -> Void
    let forward: () -> Void
    private unowned let delegate: IntraDocumentNavigationButtonsHandlerDelegate
    /// View the buttons are added to.
    private weak var containerView: UIView?
    /// View the buttons are laid out against. Must be a subview of `containerView`.
    private weak var documentView: UIView?
    /// Provides PSPDFKit's user interface view, whose scrubber bar is inset so that it doesn't go under visible buttons. A provider is used,
    /// since the PDF controller (and its user interface view) can be created after this handler.
    private let userInterfaceViewProvider: () -> UserInterfaceView?
    // Widths of buttons that may not exist yet, measured with throwaway buttons.
    private var measuredWidths: [MeasuredWidthKey: CGFloat] = [:]

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
        userInterfaceViewProvider: @escaping () -> UserInterfaceView?,
        back: @escaping () -> Void,
        forward: @escaping () -> Void,
        delegate: IntraDocumentNavigationButtonsHandlerDelegate
    ) {
        self.containerView = containerView
        self.documentView = documentView
        self.userInterfaceViewProvider = userInterfaceViewProvider
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
        updateScrubberBarInsets()
    }

    /// Insets the scrubber bar equally on both sides, so that it stays centered and its floating content stays clear of the buttons, while any
    /// button is visible. The inset is based on the wider of both buttons, even if only one of them is visible (or created), so that the scrubber
    /// bar doesn't jump when the other one appears. PSPDFKit already keeps a margin between the bar's frame and its floating content, so the inset
    /// is reduced by it, letting the content reach the buttons. Called whenever a button is shown, hidden or changes its title.
    private func updateScrubberBarInsets() {
        guard let userInterfaceView = userInterfaceViewProvider(), let containerView else { return }
        let visibleButtons = [backButton, forwardButton].compactMap({ $0 }).filter({ !$0.isHidden })
        var maxButtonWidth: CGFloat = 0
        if !visibleButtons.isEmpty {
            let traitCollection = containerView.traitCollection
            let showsTitle = Self.showsTitle(for: traitCollection)
            maxButtonWidth = max(
                measuredWidth(of: .back, showsTitle: showsTitle, contentSizeCategory: traitCollection.preferredContentSizeCategory),
                measuredWidth(of: .forward, showsTitle: showsTitle, contentSizeCategory: traitCollection.preferredContentSizeCategory)
            )
        }
        let horizontalInset = maxButtonWidth > 0 ? max(0, Self.horizontalInset + maxButtonWidth - Self.floatingScrubberBarContentMargin) : 0
        var insets = userInterfaceView.scrubberBarInsets
        guard insets.left != horizontalInset || insets.right != horizontalInset else { return }
        insets.left = horizontalInset
        insets.right = horizontalInset
        userInterfaceView.scrubberBarInsets = insets
        // Reposition the scrubber bar right away, so that it doesn't lag behind the buttons.
        userInterfaceView.setNeedsLayout()
        userInterfaceView.layoutIfNeeded()
    }

    /// Width a button has (or would have), measured with a throwaway button so that buttons that aren't needed aren't created.
    private func measuredWidth(of kind: Kind, showsTitle: Bool, contentSizeCategory: UIContentSizeCategory) -> CGFloat {
        let key = MeasuredWidthKey(kind: kind, showsTitle: showsTitle, contentSizeCategory: contentSizeCategory)
        if let width = measuredWidths[key] {
            return width
        }
        let button = UIButton(configuration: Self.configuration(for: kind, showsTitle: showsTitle))
        button.traitOverrides.preferredContentSizeCategory = contentSizeCategory
        button.updateConfiguration()
        let width = ceil(button.intrinsicContentSize.width)
        measuredWidths[key] = width
        return width
    }

    /// Size class is unspecified until a view is in a window, so only an explicitly regular size class shows the titles.
    private static func showsTitle(for traitCollection: UITraitCollection) -> Bool {
        return traitCollection.horizontalSizeClass == .regular
    }

    private static func configuration(for kind: Kind, showsTitle: Bool) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: kind.imageSystemName, withConfiguration: UIImage.SymbolConfiguration(scale: .small))
        configuration.title = showsTitle ? kind.title : nil
        configuration.baseForegroundColor = Asset.Colors.zoteroBlueWithDarkMode.color
        configuration.background.backgroundColor = Asset.Colors.navbarBackground.color
        configuration.imagePadding = 8
        return configuration
    }

    private func createButton(kind: Kind) -> UIButton? {
        guard let containerView, let documentView else { return nil }
        let action: UIAction
        switch kind {
        case .back:
            action = UIAction(handler: { [weak self] _ in self?.back() })

        case .forward:
            action = UIAction(handler: { [weak self] _ in self?.forward() })
        }

        let button = UIButton(configuration: Self.configuration(for: kind, showsTitle: false))
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

        // Now that the button is in the view hierarchy, its traits are the container's, so the initial title matches the current size class.
        // Update the title as soon as the horizontal size class changes, before the layout for the new size runs, so that the button gets sized
        // for its new content. A `configurationUpdateHandler` would apply the title later, during the button's own layout, after its frame has
        // already been determined, which can leave the button truncated until the next layout.
        updateTitle(of: button)
        button.registerForTraitChanges([UITraitHorizontalSizeClass.self]) { [weak self] (button: UIButton, _: UITraitCollection) in
            updateTitle(of: button)
            // The button's width changed with its title, so the scrubber bar insets need to follow.
            self?.updateScrubberBarInsets()
        }

        // Lay out the new button right away, so that its frame is valid for callers reading it (e.g. the annotation toolbar's available size).
        UIView.performWithoutAnimation {
            containerView.layoutIfNeeded()
        }
        return button

        func updateTitle(of button: UIButton) {
            let showsTitle = Self.showsTitle(for: button.traitCollection)
            var configuration = button.configuration
            configuration?.title = showsTitle ? kind.title : nil
            button.configuration = configuration
            // Trait changes can be delivered in the middle of a layout pass, after the container has already sized the button. Apply the new
            // configuration now, so that the intrinsic content size reflects the title, and request another layout of the container, so that the
            // button is resized. `layoutIfNeeded` isn't used, since forcing layout from within a layout pass can be re-entrant.
            button.updateConfiguration()
            button.invalidateIntrinsicContentSize()
            button.superview?.setNeedsLayout()
        }
    }
}
