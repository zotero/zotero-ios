//
//  UIViewController+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift

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
        self.window?.windowScene?.userActivity = userActivity
        userActivity.becomeCurrent()
    }

    private var window: UIWindow? {
        if let viewController = self.presentingViewController {
            return viewController.view.window
        }
        return self.view.window
    }
}
