//
//  UIViewController+Extensions.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

extension UIViewController {
    func showAlert(for error: Error, cancelled: @escaping () -> Void) {
        let controller = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: "Ok", style: .cancel, handler: { _ in
            cancelled()
        }))
        self.present(controller, animated: true, completion: nil)
    }

    var topController: UIViewController {
        var topController = self
        while let presented = topController.presentedViewController {
            topController = presented
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
