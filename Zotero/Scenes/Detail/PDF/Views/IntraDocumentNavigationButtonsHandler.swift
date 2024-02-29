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
    var showsBackButton: Bool {
        backButton?.isHidden == false
    }

    init(parent: UIViewController, back: @escaping () -> Void) {
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

        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor, constant: 30),
            parent.view.bottomAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 80)
        ])
    }

    func set(backButtonVisible: Bool) {
        backButton.isHidden = !backButtonVisible
    }
}
