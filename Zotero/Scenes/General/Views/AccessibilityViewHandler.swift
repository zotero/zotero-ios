//
//  AccessibilityViewHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 01.07.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import AVFAudio
import UIKit

protocol AccessibilityViewDelegate: AnyObject {
    var isNavigationBarHidden: Bool { get }
    func showAccessibilityPopup<Delegate: SpeechManagerDelegate>(
        speechManager: SpeechManager<Delegate>,
        sender: UIBarButtonItem,
        animated: Bool,
        isFormSheet: @escaping () -> Bool,
        dismissAction: @escaping () -> Void,
        voiceChangeAction: @escaping (AccessibilityPopupVoiceChange) -> Void
    )
    func accessibilityToolbarChanged(height: CGFloat)
    func addAccessibilityControlsViewToAnnotationToolbar(view: AnnotationToolbarLeadingView)
    func removeAccessibilityControlsViewFromAnnotationToolbar()
}

final class AccessibilityViewHandler<Delegate: SpeechManagerDelegate> {
    let navbarButtonTag = 4
    private unowned let viewController: UIViewController
    private unowned let documentContainer: UIView
    private unowned let dbStorage: DbStorage
    let speechManager: SpeechManager<Delegate>
    private let key: String
    private let libraryId: LibraryIdentifier

    private weak var activeOverlay: AccessibilitySpeechControlsView<Delegate>?
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

    init(key: String, libraryId: LibraryIdentifier, viewController: UIViewController, documentContainer: UIView, delegate: Delegate, dbStorage: DbStorage, remoteVoicesController: RemoteVoicesController) {
        self.key = key
        self.libraryId = libraryId
        self.viewController = viewController
        self.documentContainer = documentContainer
        self.dbStorage = dbStorage
        let language = try? dbStorage.perform(request: ReadSpeechLanguageDbRequest(key: key, libraryId: libraryId), on: .main)
        speechManager = SpeechManager(delegate: delegate, voiceLanguage: language, useRemoteVoices: Defaults.shared.isUsingRemoteVoice, remoteVoicesController: remoteVoicesController)
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

    func showSpeech(sender: UIBarButtonItem? = nil, isCompact: Bool = false, animated: Bool = true) {
        guard let sender = sender ?? viewController.navigationItem.leftBarButtonItems?.first(where: { $0.tag == navbarButtonTag }) else { return }
        hideOverlay()
        reloadSpeechButton(isSelected: true)
        delegate?.showAccessibilityPopup(
            speechManager: speechManager,
            sender: sender,
            animated: animated,
            isFormSheet: { [weak self] in self?.isFormSheet ?? false },
            dismissAction: { [weak self] in
                guard let self else { return }
                showOverlayIfNeeded(forType: currentOverlayType(controller: self))
                reloadSpeechButton(isSelected: false)
            },
            voiceChangeAction: { [weak self] change in
                self?.processVoiceChange(change)
            }
        )
        
        func currentOverlayType(controller: AccessibilityViewHandler<Delegate>) -> AccessibilitySpeechControlsView<Delegate>.Kind {
            if controller.isFormSheet {
                return .bottomToolbar
            } else if !(controller.delegate?.isNavigationBarHidden ?? true) {
                return .navbar
            } else {
                return .annotationToolbar
            }
        }
    }

    private func processVoiceChange(_ change: AccessibilityPopupVoiceChange) {
        try? dbStorage.perform(request: SetSpeechLanguageDbRequest(key: key, libraryId: libraryId, language: change.preferredLanguage), on: .main)
        speechManager.set(voice: change.voice, voiceLanguage: change.voiceLanguage, preferredLanguage: change.preferredLanguage, remainingCredits: change.remainingCredits)
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
        showOverlayIfNeeded(forType: type)
    }

    private func showOverlayIfNeeded(forType type: AccessibilitySpeechControlsView<Delegate>.Kind) {
        guard speechManager.state.value != .stopped, activeOverlay?.type != type else { return }
        
        if let activeOverlay {
            remove(activeControls: activeOverlay)
        }

        let overlay = AccessibilitySpeechControlsView(type: type, speechManager: speechManager)
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
                overlay.trailingAnchor.constraint(equalTo: documentContainer.trailingAnchor),
                overlay.controlsView.bottomAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor)
            ])

            delegate?.accessibilityToolbarChanged(height: overlay.frame.height)
            viewController.view.layoutIfNeeded()
        }

        func showInNavigationBar() {
            viewController.navigationItem.titleView = overlay
        }
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
