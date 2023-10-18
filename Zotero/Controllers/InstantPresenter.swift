//
//  InstantPresenter.swift
//  Zotero
//
//  Created by Miltiadis Vasilakis on 18/10/23.
//  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjackSwift

protocol InstantPresenter: AnyObject {
    var presentedRestoredControllerWindow: UIWindow? { get set }
    
    func show(controller: UIViewController, by presenter: UIViewController, in window: UIWindow, animated: Bool, completion: (() -> Void)?)
}

extension InstantPresenter {
    func show(controller: UIViewController, by presenter: UIViewController, in window: UIWindow, animated: Bool, completion: (() -> Void)? = nil) {
        DDLogInfo("InstantPresenter: show controller; animated=\(animated)")
        
        if animated {
            if presenter.presentedViewController == nil {
                DDLogInfo("InstantPresenter: no presented controller, present controller")
                presenter.present(controller, animated: true, completion: completion)
                return
            }
            
            DDLogInfo("InstantPresenter: previously presented controller, dismiss")
            presenter.dismiss(animated: true, completion: {
                DDLogInfo("InstantPresenter: present controller")
                presenter.present(controller, animated: true, completion: completion)
            })
            return
        }
        
        show(presentedViewController: controller, by: presenter, in: window) { presenter, completion in
            if presenter.presentedViewController == nil {
                DDLogInfo("InstantPresenter: no presented controller, present controller")
                presenter.present(controller, animated: false, completion: completion)
                return
            }
            
            DDLogInfo("InstantPresenter: previously presented controller, dismiss")
            presenter.dismiss(animated: false, completion: {
                DDLogInfo("InstantPresenter: present controller")
                presenter.present(controller, animated: false, completion: completion)
            })
        }
        
        completion?()
        
        /// If the app tries to present a `UIViewController` on a `UIWindow` that is being shown after app launches,
        /// there is a small delay where the underlying (presenting) `UIViewController` is visible.
        /// So the launch animation looks bad, since you can see a snapshot of previous state (PDF reader),
        /// then split view controller with collections and items and then PDF reader again.
        /// Because of that we fake it a little with this function.
        func show(presentedViewController: UIViewController, by presenter: UIViewController, in window: UIWindow, presentAction: (UIViewController, @escaping () -> Void) -> Void) {
            // Store original rootViewController
            guard let oldRootViewController = window.rootViewController else { return }
            
            // Show new view controller in the window so that it's layed out properly
            window.rootViewController = presentedViewController
            
            // Make a screenshot of the window
            UIGraphicsBeginImageContext(window.frame.size)
            window.layer.render(in: UIGraphicsGetCurrentContext()!)
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            // Create a temporary `UIImageView` with given screenshot
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFill
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            imageView.frame = window.bounds
            
            // Create a temporary `UIWindow` which will be shown above current window until it successfully presents the new view controller.
            let tmpWindow = UIWindow(frame: window.frame)
            tmpWindow.windowScene = window.windowScene
            tmpWindow.addSubview(imageView)
            tmpWindow.makeKeyAndVisible()
            presentedRestoredControllerWindow = tmpWindow
            
            // New window is visible with a screenshot, restore original rootViewController and present
            window.rootViewController = oldRootViewController
            
            presentAction(presenter) {
                // Clean up temprary window
                self.presentedRestoredControllerWindow = nil
            }
        }
    }
}
