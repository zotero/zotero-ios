//
//  UIViewController+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift

extension UIResponder {
    @objc var scene: UIScene? {
        nil
    }
}

extension UIViewController {
    func showAlert(for error: Error, cancelled: @escaping () -> Void) {
        let controller = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: "Ok", style: .cancel, handler: { _ in
            cancelled()
        }))
        self.present(controller, animated: true, completion: nil)
    }

    var topController: UIViewController {
        // We were getting some infinite-loop crashes here. So for debugging and to get rid of crash, we're checking which controllers repeat.
        var controllers: [UIViewController] = [self]
        var topController = self
        while let presented = topController.presentedViewController {
            if controllers.contains(presented) {
                let controllerNames = controllers.map({ String(describing: $0) })
                DDLogError("UIViewController: topController inifnite loop, repeating controller: \(String(describing: presented)), controllers: \(controllerNames)")
                break
            }
            topController = presented
            controllers.append(presented)
        }
        return topController
    }

    func set(userActivity: NSUserActivity) {
        if let scene {
            scene.userActivity = userActivity
            scene.title = userActivity.title
        }
        userActivity.becomeCurrent()
    }

    private var window: UIWindow? {
        if let viewController = self.presentingViewController {
            return viewController.view.window
        }
        return self.view.window
    }

    @objc override var scene: UIScene? {
        // From https://stackoverflow.com/questions/56588843/uiapplication-shared-delegate-equivalent-for-scenedelegate-xcode11/56589151#56589151
        // Traversing the responder chain to find the scene this view controller belongs to. Trying sibling(s).
        if let scene = next?.scene {
            return scene
        }
        // Sibling responder(s) didn't return a scene. Trying parent.
        if let scene = parent?.scene {
            return scene
        }
        // Parent also didn't return a scene. Trying presenting view controller.
        return presentingViewController?.scene
    }

    var sessionIdentifier: String? {
        scene?.session.persistentIdentifier
    }
}
