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
    func showAccessibilityPopup<Delegate: SpeechmanagerDelegate>(
        speechManager: SpeechManager<Delegate>,
        sender: UIBarButtonItem,
        animated: Bool,
        isFormSheet: @escaping () -> Bool,
        dismissAction: @escaping () -> Void,
        voiceChangeAction: @escaping (AVSpeechSynthesisVoice) -> Void
    )
    func accessibilityOverlayChanged(overlayHeight: CGFloat, isOverlay: Bool)
}

final class AccessibilityViewHandler<Delegate: SpeechmanagerDelegate> {
    let navbarButtonTag = 4
    private unowned let viewController: UIViewController
    private unowned let documentContainer: UIView
    private unowned let dbStorage: DbStorage
    let speechManager: SpeechManager<Delegate>
    private let key: String
    private let libraryId: LibraryIdentifier

    private weak var activeOverlay: AccessibilityReaderOverlayView<Delegate>?
    private var overlayTop: NSLayoutConstraint?
    private var overlayLeading: NSLayoutConstraint?
    private var overlayLeadingToDocument: NSLayoutConstraint?
    private var overlayTrailingToDocument: NSLayoutConstraint?
    private var overlayBottom: NSLayoutConstraint?
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

    init(key: String, libraryId: LibraryIdentifier, viewController: UIViewController, documentContainer: UIView, delegate: Delegate, dbStorage: DbStorage) {
        self.key = key
        self.libraryId = libraryId
        self.viewController = viewController
        self.documentContainer = documentContainer
        self.dbStorage = dbStorage
        let language = try? dbStorage.perform(request: ReadSpeechLanguageDbRequest(key: key, libraryId: libraryId), on: .main)
        speechManager = SpeechManager(delegate: delegate, speechRateModifier: Defaults.shared.speechRateModifier, voiceLanguage: language)
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
                self?.showOverlayIfNeeded()
                self?.reloadSpeechButton(isSelected: false)
            },
            voiceChangeAction: { [weak self] voice in
                self?.processVoiceChange(toVoice: voice)
            }
        )
    }

    private func processVoiceChange(toVoice voice: AVSpeechSynthesisVoice) {
        try? dbStorage.perform(request: SetSpeechLanguageDbRequest(key: key, libraryId: libraryId, language: voice.baseLanguage), on: .main)
        speechManager.set(voice: voice)
    }

    private func reloadSpeechButton(isSelected: Bool) {
        guard let index = viewController.navigationItem.leftBarButtonItems?.firstIndex(where: { $0.tag == navbarButtonTag }) else { return }
        (viewController.navigationItem.leftBarButtonItems?[index].customView as? CheckboxButton)?.isSelected = isSelected
    }

    func overlayTypeDidChange() {
        guard let activeOverlay, let overlayTop, let overlayBottom, let overlayLeading, let overlayLeadingToDocument, let overlayTrailingToDocument else { return }
        if isFormSheet {
            guard overlayTop.isActive else { return }
            NSLayoutConstraint.deactivate([overlayTop, overlayLeading])
            NSLayoutConstraint.activate([overlayBottom, overlayTrailingToDocument, overlayLeadingToDocument])
            activeOverlay.change(toType: .toolbar, safeDocumentBottom: viewController.view.safeAreaLayoutGuide.bottomAnchor)
        } else {
            guard overlayBottom.isActive else { return }
            NSLayoutConstraint.deactivate([overlayBottom, overlayTrailingToDocument, overlayLeadingToDocument])
            NSLayoutConstraint.activate([overlayTop, overlayLeading])
            activeOverlay.change(toType: .overlay, safeDocumentBottom: viewController.view.safeAreaLayoutGuide.bottomAnchor)
        }
    }

    private func showOverlayIfNeeded(animated: Bool = true) {
        guard speechManager.state.value != .stopped else { return }

        let overlay = AccessibilityReaderOverlayView(type: isFormSheet ? .toolbar : .overlay, speechManager: speechManager)
        overlay.alpha = 0
        viewController.view.addSubview(overlay)
        activeOverlay = overlay

        overlayTop = overlay.topAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.topAnchor, constant: 16)
        overlayLeading = overlay.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor, constant: 16)
        overlayLeadingToDocument = overlay.leadingAnchor.constraint(equalTo: documentContainer.leadingAnchor)
        overlayTrailingToDocument = overlay.trailingAnchor.constraint(equalTo: documentContainer.trailingAnchor)
        overlayBottom = overlay.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor)

        if isFormSheet {
            showAsToolbar()
        } else {
            showAsOverlay()
        }

        func showAsOverlay() {
            NSLayoutConstraint.activate([overlayTop!, overlayLeading!])

            if animated {
                viewController.view.layoutIfNeeded()
            }

            self.delegate?.accessibilityOverlayChanged(overlayHeight: 76, isOverlay: !isFormSheet)

            if !animated {
                overlay.alpha = 1
                return
            }

            UIView.animate(
                withDuration: 0.2,
                animations: {
                    overlay.alpha = 1
                }
            )
        }

        func showAsToolbar() {
            NSLayoutConstraint.activate([overlayBottom!, overlayTrailingToDocument!, overlayLeadingToDocument!])
            overlay.connectControlsToSafeBottom(anchor: viewController.view.safeAreaLayoutGuide.bottomAnchor)

            viewController.view.layoutIfNeeded()

            self.delegate?.accessibilityOverlayChanged(overlayHeight: overlay.frame.height, isOverlay: !isFormSheet)

            if !animated {
                overlay.alpha = 1
                self.viewController.view.layoutIfNeeded()
                return
            }

            UIView.animate(
                withDuration: 0.2,
                animations: {
                    self.viewController.view.layoutIfNeeded()
                    overlay.alpha = 1
                }
            )
        }
    }

    private func hideOverlay(animated: Bool = true) {
        self.delegate?.accessibilityOverlayChanged(overlayHeight: 0, isOverlay: !isFormSheet)

        if !animated {
            self.activeOverlay?.removeFromSuperview()
            self.activeOverlay = nil
            self.viewController.view.layoutIfNeeded()
            return
        }

        UIView.animate(
            withDuration: 0.2,
            animations: {
                self.viewController.view.layoutIfNeeded()
                self.activeOverlay?.alpha = 0
            },
            completion: { success in
                guard success else { return }
                self.activeOverlay?.removeFromSuperview()
                self.activeOverlay = nil
            }
        )
    }
}
