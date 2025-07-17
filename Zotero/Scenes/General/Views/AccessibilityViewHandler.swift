//
//  AccessibilityViewHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 01.07.2025.
//  Copyright © 2025 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import RxSwift

protocol AccessibilityViewDelegate: AnyObject {
    func showAccessibilityPopup<Delegate: SpeechmanagerDelegate>(
        speechManager: SpeechManager<Delegate>,
        sender: UIBarButtonItem,
        animated: Bool,
        isFormSheet: @escaping () -> Bool,
        dismissAction: @escaping () -> Void
    )
    func accessibilityOverlayChanged(overlayHeight: CGFloat, isOverlay: Bool)
}

final class AccessibilityViewHandler<Delegate: SpeechmanagerDelegate> {
    let navbarButtonTag = 4
    private unowned let viewController: UIViewController
    private unowned let documentContainer: UIView
    let speechManager: SpeechManager<Delegate>
    private let disposeBag: DisposeBag

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

    init(viewController: UIViewController, documentContainer: UIView, speechManager: SpeechManager<Delegate>) {
        self.viewController = viewController
        self.documentContainer = documentContainer
        self.speechManager = speechManager
        disposeBag = DisposeBag()

        speechManager.state
            .skip(1)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] state in
                self?.update(state: state)
            })
            .disposed(by: disposeBag)
    }

    func createAccessibilityButton(isEnabled: Bool = true) -> UIBarButtonItem {
        let speechButton = UIBarButtonItem(image: UIImage(systemName: speechManager.isSpeaking ? "text.page.fill" : "text.page"), style: .plain, target: nil, action: nil)
        speechButton.tag = navbarButtonTag
        speechButton.isEnabled = isEnabled
        speechButton.accessibilityLabel = L10n.Accessibility.openDocumentAccessibility
        speechButton.rx.tap
            .subscribe(onNext: { [weak self, weak speechButton] _ in
                guard let self, let speechButton else { return }
                showSpeech(sender: speechButton)
            })
            .disposed(by: disposeBag)
        return speechButton
    }

    func showSpeech(sender: UIBarButtonItem? = nil, isCompact: Bool = false, animated: Bool = true) {
        guard let sender = sender ?? viewController.navigationItem.leftBarButtonItems?.first(where: { $0.tag == navbarButtonTag }) else { return }
        hideOverlay()
        delegate?.showAccessibilityPopup(speechManager: speechManager, sender: sender, animated: animated, isFormSheet: { [weak self] in self?.isFormSheet ?? false }, dismissAction: { [weak self] in
            self?.showOverlayIfNeeded()
        })
    }

    private func update(state: SpeechManager<Delegate>.State) {
        reloadSpeechButton(isSpeaking: !state.isStopped)
        func reloadSpeechButton(isSpeaking: Bool) {
            guard let index = viewController.navigationItem.leftBarButtonItems?.firstIndex(where: { $0.tag == navbarButtonTag }) else { return }
            viewController.navigationItem.leftBarButtonItems?[index] = createAccessibilityButton()
        }
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
