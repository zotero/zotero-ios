//
//  AccessibilityViewHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 01.07.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import AVFAudio
import UIKit

import RxSwift

protocol AccessibilityViewDelegate: AnyObject {
    var isNavigationBarHidden: Bool { get }
    func showAccessibilityPopup<Delegate: SpeechManagerDelegate>(
        speechManager: SpeechManager<Delegate>,
        sender: UIBarButtonItem,
        animated: Bool,
        isFormSheet: @escaping () -> Bool,
        playAction: @escaping () -> Void,
        dismissAction: @escaping () -> Void,
        highlighterAction: @escaping () -> Void,
        voiceChangeAction: @escaping (AccessibilityPopupVoiceChange) -> Void
    )
    func accessibilityToolbarChanged(height: CGFloat)
    func addAccessibilityControlsViewToAnnotationToolbar(view: AnnotationToolbarLeadingView)
    func removeAccessibilityControlsViewFromAnnotationToolbar()
    func clearSpeechHighlight()
    func showSpeechHighlighterOverlay(_ overlay: SpeechHighlighterOverlayView, isCompact: Bool, speechControlsView: UIView?, animated: Bool)
    func hideSpeechHighlighterOverlay(_ overlay: SpeechHighlighterOverlayView)
    func updateSpeechHighlightStyle(tool: AnnotationTool, color: String)
}

final class AccessibilityViewHandler<Delegate: SpeechManagerDelegate> {
    let navbarButtonTag = 4
    private unowned let viewController: UIViewController
    private unowned let documentContainer: UIView
    private unowned let dbStorage: DbStorage
    let speechManager: SpeechManager<Delegate>
    private let key: String
    private let libraryId: LibraryIdentifier
    private let disposeBag: DisposeBag

    /// Stores the last speaking position (page index + character offset) so that speech can resume from where it left off
    /// when the user returns to the same page. In-memory only, not persisted to disk.
    private var lastSpeakingPosition: (index: Delegate.Index, characterIndex: Int)?
    private weak var activeOverlay: AccessibilitySpeechControlsView<Delegate>?
    private weak var highlighterOverlay: SpeechHighlighterOverlayView?
    var isHighlighterOverlayVisible: Bool { highlighterOverlay != nil }
    weak var delegate: AccessibilityViewDelegate?
    var isFormSheet: Bool {
        // Detecting horizontalSizeClass == .compact is not reliable, as the controller can still be shown as formSheet even when horizontalSizeClass is .regular. Therefore the safest way to check
        // whether the controller is shown as form sheet or popover is to check view size. However the controller doesn't have to be visible all the time, so when the controller is not visible,
        // we just check the size class. This way there can be discrepancies between popover/formSheet and overlay/toolbar, but realistically most people won't really see this.
        if UIDevice.current.userInterfaceIdiom == .phone {
            return true
        }
        if let presentedViewController = viewController.presentedViewController {
            return viewController.view.frame.width == presentedViewController.view.frame.width
        } else {
            return viewController.traitCollection.horizontalSizeClass == .compact
        }
    }

    init(
        key: String,
        libraryId: LibraryIdentifier,
        viewController: UIViewController,
        documentContainer: UIView,
        delegate: Delegate,
        dbStorage: DbStorage,
        remoteVoicesController: RemoteVoicesController
    ) {
        self.key = key
        self.libraryId = libraryId
        self.viewController = viewController
        self.documentContainer = documentContainer
        self.dbStorage = dbStorage
        disposeBag = DisposeBag()
        let language = try? dbStorage.perform(request: ReadSpeechLanguageDbRequest(key: key, libraryId: libraryId), on: .main)
        speechManager = SpeechManager(
            delegate: delegate,
            voiceLanguage: language,
            remoteVoiceTier: Defaults.shared.remoteVoiceTier,
            remoteVoicesController: remoteVoicesController
        )

        speechManager.onSpeakingPositionChanged = { [weak self] pageIndex, characterIndex in
            self?.lastSpeakingPosition = (index: pageIndex, characterIndex: characterIndex)
        }

        speechManager.state
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                guard let self else { return }
                switch state {
                case .stopped:
                    self.dismissHighlighterOverlay(confirm: true)
                    self.delegate?.clearSpeechHighlight()
                    
                case .outOfCredits(let reason):
                    // Only show popup for daily limit - quota exceeded is handled internally by SpeechManager
                    if reason == .dailyLimitExceeded {
                        showSpeech()
                    }
                    
                case .speaking, .paused, .initializing, .loading:
                    showOverlayIfNeeded(forType: currentOverlayType(controller: self), state: state)
                }
            })
            .disposed(by: disposeBag)
    }

    func createAccessibilityButton(isSelected: Bool, isFilled: Bool, isEnabled: Bool = true) -> UIBarButtonItem {
        let button = CheckboxButton(
            image: UIImage(systemName: isFilled ? "text.page.fill" : "text.page", withConfiguration: UIImage.SymbolConfiguration(scale: .large))!.withRenderingMode(.alwaysTemplate),
            contentInsets: NSDirectionalEdgeInsets(top: 9, leading: 6, bottom: 9, trailing: 6)
        )
        button.showsLargeContentViewer = true
        button.accessibilityLabel = L10n.Accessibility.openDocumentAccessibility
        button.deselectedBackgroundColor = .clear
        button.deselectedTintColor = isEnabled ? Asset.Colors.zoteroBlueWithDarkMode.color : .gray
        button.selectedBackgroundColor = Asset.Colors.zoteroBlue.color
        button.selectedTintColor = .white
        button.isSelected = isSelected
        button.isEnabled = isEnabled
        let item = UIBarButtonItem(customView: button)
        item.tag = navbarButtonTag
        button.addAction(
            UIAction(handler: { [weak self, weak item] _ in
                guard let self, let item else { return }
                showSpeech(sender: item)
            }),
            for: .touchUpInside
        )
        return item
    }

    func startOrResumeSpeech() {
        if speechManager.state.value.isPaused {
            speechManager.resume()
        } else {
            let startIndex = resolvedStartIndex()
            speechManager.start(startIndex: startIndex)
        }

        func resolvedStartIndex() -> Int {
            guard let lastSpeakingPosition, let currentPage = speechManager.currentPageIndex, lastSpeakingPosition.index == currentPage else { return 0 }
            return lastSpeakingPosition.characterIndex
        }
    }

    func showSpeech(sender: UIBarButtonItem? = nil, isCompact: Bool = false, animated: Bool = true) {
        guard let sender = sender ?? viewController.navigationItem.leftBarButtonItems?.first(where: { $0.tag == navbarButtonTag }) else { return }
        hideOverlay()
        reloadSpeechButton(isSelected: true)
        delegate?.showAccessibilityPopup(
            speechManager: speechManager,
            sender: sender,
            animated: animated,
            isFormSheet: { [weak self] in self?.isFormSheet ?? false },
            playAction: { [weak self] in self?.startOrResumeSpeech() },
            dismissAction: { [weak self] in
                guard let self else { return }
                showOverlayIfNeeded(forType: currentOverlayType(controller: self), state: speechManager.state.value)
                reloadSpeechButton(isSelected: false)
            },
            highlighterAction: { [weak self] in
                self?.toggleHighlighterOverlay()
            },
            voiceChangeAction: { [weak self] change in
                self?.processVoiceChange(change)
            }
        )
    }
    
    private func currentOverlayType(controller: AccessibilityViewHandler<Delegate>) -> AccessibilitySpeechControlsView<Delegate>.Kind {
        if controller.isFormSheet {
            return .bottomToolbar
        } else if !(controller.delegate?.isNavigationBarHidden ?? true) {
            return .navbar
        } else {
            return .annotationToolbar
        }
    }

    private func processVoiceChange(_ change: AccessibilityPopupVoiceChange) {
        try? dbStorage.perform(request: SetSpeechLanguageDbRequest(key: key, libraryId: libraryId, language: change.preferredLanguage), on: .main)
        speechManager.set(voice: change.voice, preferredLanguage: change.preferredLanguage)
    }

    func set(initialVoice voice: SpeechVoice, language: String) {
        speechManager.set(voice: voice, voiceLanguage: language, preferredLanguage: nil)
    }

    private func reloadSpeechButton(isSelected: Bool) {
        guard let index = viewController.navigationItem.leftBarButtonItems?.firstIndex(where: { $0.tag == navbarButtonTag }) else { return }
        (viewController.navigationItem.leftBarButtonItems?[index].customView as? CheckboxButton)?.isSelected = isSelected
    }

    func accessibilityControlsShouldChange(isNavbarHidden: Bool) {
        guard activeOverlay != nil else { return }
        let type: AccessibilitySpeechControlsView<Delegate>.Kind
        if isFormSheet {
            type = .bottomToolbar
        } else if !isNavbarHidden {
            type = .navbar
        } else {
            type = .annotationToolbar
        }
        showOverlayIfNeeded(forType: type, state: speechManager.state.value)
        repositionHighlighterOverlayIfNeeded()
    }

    private func repositionHighlighterOverlayIfNeeded() {
        guard let oldOverlay = highlighterOverlay else { return }
        delegate?.hideSpeechHighlighterOverlay(oldOverlay)
        let newOverlay = SpeechHighlighterOverlayView(
            isCompact: isFormSheet,
            annotationTool: oldOverlay.selectedAnnotationTool,
            annotationColor: oldOverlay.selectedColor
        )
        newOverlay.update(text: oldOverlay.currentText)
        newOverlay.deleteAction = oldOverlay.deleteAction
        newOverlay.backwardAction = oldOverlay.backwardAction
        newOverlay.forwardAction = oldOverlay.forwardAction
        newOverlay.skipBackwardAction = oldOverlay.skipBackwardAction
        newOverlay.skipForwardAction = oldOverlay.skipForwardAction
        newOverlay.annotationToolChanged = oldOverlay.annotationToolChanged
        newOverlay.annotationColorChanged = oldOverlay.annotationColorChanged
        newOverlay.onMenuPresented = oldOverlay.onMenuPresented
        newOverlay.onMenuDismissed = oldOverlay.onMenuDismissed
        highlighterOverlay = newOverlay
        delegate?.showSpeechHighlighterOverlay(newOverlay, isCompact: isFormSheet, speechControlsView: activeOverlay, animated: false)
    }

    private func showOverlayIfNeeded(forType type: AccessibilitySpeechControlsView<Delegate>.Kind, state: SpeechState) {
        let isAccessibilityPopupPresented = (viewController.presentedViewController as? AccessibilityPopupViewController<Delegate>)?.isBeingDismissed == false
        guard !isAccessibilityPopupPresented, state != .stopped, activeOverlay?.type != type else { return }

        if let activeOverlay {
            remove(activeControls: activeOverlay)
        }

        let settingsAction: (() -> Void)?
        switch type {
        case .navbar, .bottomToolbar:
            settingsAction = { [weak self] in self?.showSpeech() }
            
        case .annotationToolbar:
            settingsAction = nil
        }
        let highlighterAction: (() -> Void)?
        switch type {
        case .navbar, .bottomToolbar:
            highlighterAction = { [weak self] in self?.toggleHighlighterOverlay() }

        case .annotationToolbar:
            highlighterAction = nil
        }
        let playAction: () -> Void = { [weak self] in self?.startOrResumeSpeech() }
        let overlay = AccessibilitySpeechControlsView(type: type, speechManager: speechManager, playAction: playAction, settingsAction: settingsAction, highlighterAction: highlighterAction)
        activeOverlay = overlay

        switch type {
        case .bottomToolbar:
            showAsBottomToolbar()

        case .annotationToolbar:
            delegate?.addAccessibilityControlsViewToAnnotationToolbar(view: overlay)

        case .navbar:
            showInNavigationBar()
        }

        func showAsBottomToolbar() {
            viewController.view.addSubview(overlay)

            NSLayoutConstraint.activate([
                overlay.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor),
                overlay.leadingAnchor.constraint(equalTo: documentContainer.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: documentContainer.trailingAnchor)
            ])

            delegate?.accessibilityToolbarChanged(height: overlay.frame.height)
            viewController.view.layoutIfNeeded()
        }

        func showInNavigationBar() {
            viewController.navigationItem.titleView = overlay
        }
    }

    private func toggleHighlighterOverlay() {
        if highlighterOverlay != nil {
            dismissHighlighterOverlay(confirm: true)
            return
        }
        guard let result = speechManager.startHighlightSession() else { return }
        let overlay = SpeechHighlighterOverlayView(
            isCompact: isFormSheet,
            annotationTool: speechManager.highlightAnnotationTool,
            annotationColor: speechManager.highlightAnnotationColor
        )
        overlay.update(text: result.text)
        overlay.deleteAction = { [weak self] in
            self?.dismissHighlighterOverlay(confirm: false)
        }
        overlay.backwardAction = { [weak self] in
            guard let self, let result = speechManager.moveHighlightBackward() else { return }
            self.highlighterOverlay?.update(text: result.text)
        }
        overlay.forwardAction = { [weak self] in
            guard let self, let result = speechManager.moveHighlightForward() else { return }
            self.highlighterOverlay?.update(text: result.text)
        }
        overlay.skipBackwardAction = { [weak self] in
            guard let self, let result = speechManager.extendHighlightBackward() else { return }
            self.highlighterOverlay?.update(text: result.text)
        }
        overlay.skipForwardAction = { [weak self] in
            guard let self, let result = speechManager.extendHighlightForward() else { return }
            self.highlighterOverlay?.update(text: result.text)
        }
        overlay.annotationToolChanged = { [weak self] tool in
            guard let self else { return }
            speechManager.setHighlightAnnotationTool(tool)
            delegate?.updateSpeechHighlightStyle(tool: tool, color: speechManager.highlightAnnotationColor)
        }
        overlay.annotationColorChanged = { [weak self] color in
            guard let self else { return }
            speechManager.setHighlightAnnotationColor(color)
            delegate?.updateSpeechHighlightStyle(tool: speechManager.highlightAnnotationTool, color: color)
        }
        overlay.onMenuPresented = { [weak self] in
            self?.speechManager.stopHighlightInactivityTimer()
        }
        overlay.onMenuDismissed = { [weak self] in
            self?.speechManager.startHighlightInactivityTimer()
        }
        speechManager.onHighlightSessionTimedOut = { [weak self] in
            self?.dismissHighlighterOverlay(confirm: true)
        }
        highlighterOverlay = overlay
        delegate?.showSpeechHighlighterOverlay(overlay, isCompact: isFormSheet, speechControlsView: activeOverlay, animated: true)
    }

    private func dismissHighlighterOverlay(confirm: Bool) {
        if confirm {
            speechManager.endHighlightSession()
        } else {
            speechManager.cancelHighlightSession()
        }
        speechManager.onHighlightSessionTimedOut = nil
        guard let overlay = highlighterOverlay else { return }
        delegate?.hideSpeechHighlighterOverlay(overlay)
        highlighterOverlay = nil
    }

    func confirmActiveHighlightSession() {
        guard highlighterOverlay != nil else { return }
        dismissHighlighterOverlay(confirm: true)
    }

    func cancelActiveHighlightSession() {
        guard highlighterOverlay != nil else { return }
        dismissHighlighterOverlay(confirm: false)
    }

    func performHighlighterAction(_ action: (SpeechHighlighterOverlayView) -> Void) {
        guard let overlay = highlighterOverlay else { return }
        action(overlay)
    }

    private func hideOverlay() {
        guard let activeOverlay else { return }
        remove(activeControls: activeOverlay)
        self.activeOverlay = nil
        viewController.view.layoutIfNeeded()
    }
    
    private func remove(activeControls: AccessibilitySpeechControlsView<Delegate>) {
        switch activeControls.type {
        case .navbar:
            viewController.navigationItem.titleView = nil
            
        case .bottomToolbar:
            delegate?.accessibilityToolbarChanged(height: 0)
            activeControls.removeFromSuperview()
            
        case .annotationToolbar:
            delegate?.removeAccessibilityControlsViewFromAnnotationToolbar()
        }
    }
}
