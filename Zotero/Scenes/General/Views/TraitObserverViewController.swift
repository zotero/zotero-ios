//
//  TraitObserverViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 07.04.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

final class TraitObserverViewController: UIViewController {
    private let onChange: (UITraitCollection) -> Void

    init(onChange: @escaping (UITraitCollection) -> Void) {
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if let previousTraitCollection, traitCollection.horizontalSizeClass != previousTraitCollection.horizontalSizeClass {
            onChange(traitCollection)
        }
    }
}
