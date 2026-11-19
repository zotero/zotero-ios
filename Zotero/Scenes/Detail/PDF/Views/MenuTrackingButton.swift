//
//  MenuTrackingButton.swift
//  Zotero
//
//  Created by Michal Rentka on 14/05/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class MenuTrackingButton: UIButton {
    var menuWillPresent: (() -> Void)?
    var menuDidDismiss: (() -> Void)?

    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willDisplayMenuFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
        menuWillPresent?()
    }

    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        guard let animator else {
            DispatchQueue.main.async { [weak self] in
                self?.menuDidDismiss?()
            }
            return
        }
        animator.addCompletion { [weak self] in
            self?.menuDidDismiss?()
        }
    }
}
