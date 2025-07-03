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
    func showAccessibilityPopup<Delegate: SpeechmanagerDelegate>(speechManager: SpeechManager<Delegate>, sender: UIBarButtonItem, dismissAction: @escaping () -> Void)
    func accessibilityOverlayChanged(overlayHeight: CGFloat)
}

final class AccessibilityViewHandler<Delegate: SpeechmanagerDelegate> {
    let navbarButtonTag = 4
    private unowned let viewController: UIViewController
    private let speechManager: SpeechManager<Delegate>
    private let disposeBag: DisposeBag

    private weak var activeOverlay: AccessibilityReaderOverlayView<Delegate>?
    weak var delegate: AccessibilityViewDelegate?

    init(viewController: UIViewController, speechManager: SpeechManager<Delegate>) {
        self.viewController = viewController
        disposeBag = DisposeBag()
        self.speechManager = speechManager

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

    func showSpeech(sender: UIBarButtonItem? = nil) {
        guard let sender = sender ?? viewController.navigationItem.leftBarButtonItems?.first(where: { $0.tag == navbarButtonTag }) else { return }
        hideOverlay()
        delegate?.showAccessibilityPopup(speechManager: speechManager, sender: sender, dismissAction: { [weak self] in
            self?.showOverlayIfNeeded()
        })
    }

    private func update(state: SpeechManager<Delegate>.State) {
        reloadSpeechButton(isSpeaking: state.isSpeakingOrLoading)

        func reloadSpeechButton(isSpeaking: Bool) {
            guard let index = viewController.navigationItem.leftBarButtonItems?.firstIndex(where: { $0.tag == navbarButtonTag }) else { return }
            viewController.navigationItem.leftBarButtonItems?[index] = createAccessibilityButton()
        }
    }

    private func showOverlayIfNeeded() {
        guard speechManager.state.value != .stopped else { return }

        let overlay = AccessibilityReaderOverlayView(speechManager: speechManager)
        overlay.alpha = 0
        viewController.view.addSubview(overlay)
        activeOverlay = overlay

        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.topAnchor, constant: 16),
            overlay.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor, constant: 16)
        ])
        viewController.view.layoutIfNeeded()

        self.delegate?.accessibilityOverlayChanged(overlayHeight: 76)

        UIView.animate(
            withDuration: 0.2,
            animations: {
                overlay.alpha = 1
            }
        )
    }

    private func hideOverlay() {
        self.delegate?.accessibilityOverlayChanged(overlayHeight: 0)

        UIView.animate(
            withDuration: 0.2,
            animations: {
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
