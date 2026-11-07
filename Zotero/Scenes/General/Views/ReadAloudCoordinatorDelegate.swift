//
//  ReadAloudCoordinatorDelegate.swift
//  Zotero
//
//  Created by Michal Rentka on 12.08.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit
import SafariServices
import SwiftUI

protocol ReadAloudCoordinatorDelegate: AnyObject {
    var navigationController: UINavigationController? { get }
    var remoteVoicesController: RemoteVoicesController { get }

    func showVoicePicker(
        for voice: SpeechVoice,
        language: String?,
        detectedLanguage: String,
        userInterfaceStyle: UIUserInterfaceStyle,
        selectionChanged: @escaping (ReadAloudVoiceChange) -> Void
    )
    func showReadAloudOnboarding(
        from presenter: UIViewController,
        language: String?,
        detectedLanguage: String,
        userInterfaceStyle: UIUserInterfaceStyle,
        completion: @escaping (SpeechVoice?) -> Void
    )
    func showReadAloudAddMoreTime(from presenter: UIViewController)
}

extension ReadAloudCoordinatorDelegate {
    func showVoicePicker(
        for voice: SpeechVoice,
        language: String?,
        detectedLanguage: String,
        userInterfaceStyle: UIUserInterfaceStyle,
        selectionChanged: @escaping (ReadAloudVoiceChange) -> Void
    ) {
        guard let navigationController else { return }
        let view = ReadAloudVoicePickerView(
            selectedVoice: voice,
            language: language,
            detectedLanguage: detectedLanguage,
            remoteVoicesController: remoteVoicesController,
            dismiss: { change in
                selectionChanged(change)
                navigationController.dismiss(animated: true)
            }
        )
        let controller = UIHostingController(rootView: view)
        controller.overrideUserInterfaceStyle = userInterfaceStyle
        controller.modalPresentationStyle = .formSheet
        controller.isModalInPresentation = true
        if let presentedController = navigationController.presentedViewController {
            presentedController.present(controller, animated: true)
        } else {
            navigationController.present(controller, animated: true)
        }
    }

    func showReadAloudOnboarding(from presenter: UIViewController, language: String?, detectedLanguage: String, userInterfaceStyle: UIUserInterfaceStyle, completion: @escaping (SpeechVoice?) -> Void) {
        let view = ReadAloudOnboardingView(
            language: language,
            detectedLanguage: detectedLanguage,
            remoteVoicesController: remoteVoicesController,
            dismiss: { selectedVoice in
                presenter.dismiss(animated: true) {
                    completion(selectedVoice)
                }
            }
        )
        let controller = UIHostingController(rootView: view)
        controller.overrideUserInterfaceStyle = userInterfaceStyle
        controller.modalPresentationStyle = .formSheet
        presenter.present(controller, animated: true)
    }

    func showReadAloudAddMoreTime(from presenter: UIViewController) {
        guard let url = URL(string: "https://www.zotero.org/settings/readaloud") else { return }
        let controller = SFSafariViewController(url: url)
        controller.modalPresentationStyle = .formSheet
        (presenter.presentedViewController ?? presenter).present(controller, animated: true)
    }
}
