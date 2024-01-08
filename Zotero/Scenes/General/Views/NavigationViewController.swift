//
//  NavigationViewController.swift
//  Zotero
//
//  Created by Michal Rentka on 08.12.2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

class NavigationViewController: UINavigationController {
    var dismissHandler: (() -> Void)?
    var statusBarVisible: Bool = true

    override var prefersStatusBarHidden: Bool {
        return !statusBarVisible
    }

    deinit {
        dismissHandler?()
    }
}

class DetailNavigationViewController: NavigationViewController {
    weak var coordinator: Coordinator?
    public func replaceContents(with replacement: DetailNavigationViewController, animated: Bool) {
        // Set replacement properties to self.
        // Swap coordinators and dismiss handlers, so that the original coordinator is properly deinitialized, along with the original view controllers.
        // Swap also the navigation controller property of the two coordinators.
        // Store original
        let originalCoordinator = coordinator
        let originalDismissHandler = dismissHandler
        // Swap replacement to original
        coordinator = replacement.coordinator
        coordinator?.navigationController = self
        dismissHandler = replacement.dismissHandler
        statusBarVisible = replacement.statusBarVisible
        setViewControllers(replacement.viewControllers, animated: animated)
        // Swap original to replacement
        replacement.coordinator = originalCoordinator
        replacement.coordinator?.navigationController = replacement
        replacement.dismissHandler = originalDismissHandler
    }
}
