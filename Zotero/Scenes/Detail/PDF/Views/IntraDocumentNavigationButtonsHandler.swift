//
//  IntraDocumentNavigationButtonsHandler.swift
//  Zotero
//
//  Created by Michal Rentka on 19.02.2024.
//  Copyright © 2024 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class IntraDocumentNavigationButtonsHandler {
    private weak var backButton: UIButton!
    private weak var forwardButton: UIButton!

    init(parent: UIViewController, back: @escaping () -> Void, forward: @escaping () -> Void) {
        var backConfiguration = UIButton.Configuration.plain()
        backConfiguration.title = L10n.back
        backConfiguration.image = UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(scale: .small))
        backConfiguration.baseForegroundColor = Asset.Colors.zoteroBlueWithDarkMode.color
        backConfiguration.background.backgroundColor = Asset.Colors.navbarBackground.color
        backConfiguration.imagePadding = 8
        let backButton = UIButton(configuration: backConfiguration)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.isHidden = true
        backButton.addAction(
            UIAction(handler: { _ in back() }),
            for: .touchUpInside
        )
        parent.view.addSubview(backButton)
        self.backButton = backButton

        var forwardConfiguration = UIButton.Configuration.plain()
        forwardConfiguration.title = L10n.forward
        forwardConfiguration.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(scale: .small))
        forwardConfiguration.baseForegroundColor = Asset.Colors.zoteroBlueWithDarkMode.color
        forwardConfiguration.background.backgroundColor = Asset.Colors.navbarBackground.color
        forwardConfiguration.imagePadding = 8
        forwardConfiguration.imagePlacement = .trailing
        let forwardButton = UIButton(configuration: forwardConfiguration)
        forwardButton.translatesAutoresizingMaskIntoConstraints = false
        forwardButton.isHidden = true
        forwardButton.addAction(
            UIAction(handler: { _ in forward() }),
            for: .touchUpInside
        )
        parent.view.addSubview(forwardButton)
        self.forwardButton = forwardButton

        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor, constant: 30),
            parent.view.bottomAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 80),
            parent.view.trailingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 30),
            parent.view.bottomAnchor.constraint(equalTo: forwardButton.bottomAnchor, constant: 80)
        ])
    }

    func set(backButtonVisible: Bool, forwardButtonVisible: Bool) {
        backButton.isHidden = !backButtonVisible
        forwardButton.isHidden = !forwardButtonVisible
    }
}
