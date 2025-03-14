//
//  IntraDocumentNavigationButtonsHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 19.02.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class IntraDocumentNavigationButtonsHandler {
    let back: () -> Void
    let forward: () -> Void
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

    init(back: @escaping () -> Void, forward: @escaping () -> Void) {
        self.back = back
        self.forward = forward
    }

    func set(backButtonVisible: Bool, forwardButtonVisible: Bool) {
        backButton.isHidden = !backButtonVisible
        forwardButton.isHidden = !forwardButtonVisible
        backButton.superview?.bringSubviewToFront(backButton)
        forwardButton.superview?.bringSubviewToFront(forwardButton)
    }

    private func createButton(title: String, imageSystemName: String, action: UIAction) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: imageSystemName, withConfiguration: UIImage.SymbolConfiguration(scale: .small))
        configuration.baseForegroundColor = Asset.Colors.zoteroBlueWithDarkMode.color
        configuration.background.backgroundColor = Asset.Colors.navbarBackground.color
        configuration.imagePadding = 8
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.defaultHigh, for: .vertical)
        button.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        button.isHidden = true
        button.addAction(action, for: .touchUpInside)
        return button
    }
}
