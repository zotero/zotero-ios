//
//  AppCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 03/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import SwiftUI
import UIKit

protocol AppDelegateCoordinatorDelegate: class {
    func showMainScreen(isLoggedIn: Bool)
}

class AppCoordinator {
    private typealias Action = (UIViewController) -> Void

    private let controllers: Controllers

    private weak var window: UIWindow?
    private var viewController: UIViewController? {
        guard let viewController = self.window?.rootViewController else { return nil }
        var topController = viewController.topController
        topController = (topController as? MainViewController)?.viewControllers.last ?? topController
        return topController
    }

    init(window: UIWindow?, controllers: Controllers) {
        self.window = window
        self.controllers = controllers
    }

    func start() {
        self.showMainScreen(isLogged: self.controllers.sessionController.isLoggedIn, animated: false)

        self.controllers.debugLogging.coordinator = self
        self.controllers.crashReporter.coordinator = self
        self.controllers.translatorsController.coordinator = self
    }

    // MARK: - Navigation

    private func showMainScreen(isLogged: Bool, animated: Bool) {
        let viewController: UIViewController
        if !isLogged {
            let onboardingController = OnboardingViewController(htmlConverter: self.controllers.htmlAttributedStringConverter,
                                                                apiClient: self.controllers.apiClient,
                                                                sessionController: self.controllers.sessionController)
            let navigationController = UINavigationController(rootViewController: onboardingController)
            viewController = navigationController
            self.controllers.userControllers?.syncScheduler.syncController.set(coordinator: nil)
        } else {
            viewController = MainViewController(controllers: self.controllers)
            self.controllers.userControllers?.syncScheduler.syncController.set(coordinator: self)
        }
        self.show(viewController: viewController, animated: animated)
    }

    private func show(viewController: UIViewController?, animated: Bool = false) {
        guard let window = self.window else { return }

        window.rootViewController = viewController

        guard animated else { return }

        UIView.transition(with: window, duration: 0.2, options: .transitionCrossDissolve, animations: {}, completion: { _ in })
    }

    private func presentActivityViewController(with items: [Any], completed: @escaping () -> Void) {
        guard let viewController = self.viewController else { return }

        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { (_, _, _, _) in
            completed()
        }

        controller.popoverPresentationController?.sourceView = viewController.view
        controller.popoverPresentationController?.sourceRect = viewController.view.frame.insetBy(dx: 100, dy: 100)
        viewController.present(controller, animated: true, completion: nil)
    }

    private func showAlert(title: String, message: String, actions: [UIAlertAction]) {
        let controller = UIAlertController(title: title, message: message, preferredStyle: .alert)
        actions.forEach({ controller.addAction($0) })
        self.viewController?.present(controller, animated: true, completion: nil)
    }
}

extension AppCoordinator: AppDelegateCoordinatorDelegate {
    func showMainScreen(isLoggedIn: Bool) {
        self.showMainScreen(isLogged: isLoggedIn, animated: true)
    }
}

extension AppCoordinator: DebugLoggingCoordinator {
    func share(logs: [URL], completed: @escaping () -> Void) {
        self.presentActivityViewController(with: logs, completed: completed)
    }

    func show(error: DebugLogging.Error) {
        let message: String
        switch error {
        case .start:
            message = "Can't start debug logging."
        case .contentReading:
            message = "Can't find log files."
        }
        self.showAlert(title: "Debugging error",
                       message: message,
                       actions: [UIAlertAction(title: "Ok", style: .cancel, handler: nil)])
    }
}

extension AppCoordinator: CrashReporterCoordinator {
    func report(crash: String, completed: @escaping () -> Void) {
        let actions = [UIAlertAction(title: "No", style: .cancel, handler: { _ in completed() }),
                       UIAlertAction(title: "Yes", style: .default, handler: { [weak self] action in
                           self?.presentActivityViewController(with: [crash], completed: completed)
                       })]
        self.showAlert(title: "Crash report",
                        message: "It seems you encountered a crash. Would you like to report it?",
                        actions: actions)
    }
}

extension AppCoordinator: TranslatorsControllerCoordinatorDelegate {
    func showRemoteLoadTranslatorsError(result: @escaping (Bool) -> Void) {
        self.showAlert(title: "Translators error",
                       message: "Could not load translator updates. Would you like to try again?",
                       actions: [UIAlertAction(title: "No", style: .cancel, handler: { _ in result(false) }),
                                 UIAlertAction(title: "Yes", style: .default, handler: { _ in result(true) })])
    }

    func showBundleLoadTranslatorsError(result: @escaping (Bool) -> Void) {
        self.showAlert(title: "Translators error",
                       message: "Could not update translators from bundle. Would you like to try again?",
                       actions: [UIAlertAction(title: "No", style: .cancel, handler: { _ in result(false) }),
                                 UIAlertAction(title: "Yes", style: .default, handler: { _ in result(true) })])
    }

    func showResetToBundleError() {
        self.showAlert(title: "Translators error",
                       message: "Could not load bundled translators.",
                       actions: [UIAlertAction(title: "Ok", style: .cancel, handler: nil)])
    }
}

extension AppCoordinator: ConflictReceiver {
    func resolve(conflict: Conflict, completed: @escaping (ConflictResolution?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?._resolve(conflict: conflict, completed: completed)
        }
    }

    private func _resolve(conflict: Conflict, completed: @escaping (ConflictResolution?) -> Void) {
        let (title, message, actions) = self.createAlert(for: conflict, completed: completed)

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        actions.forEach { action in
            alert.addAction(action)
        }
        self.viewController?.present(alert, animated: true, completion: nil)
    }

    private func createAlert(for conflict: Conflict, completed: @escaping (ConflictResolution?) -> Void)
                                                                                       -> (title: String, message: String, actions: [UIAlertAction]) {
        switch conflict {
        case .groupRemoved(let groupId, let groupName):
            let actions = [UIAlertAction(title: "Remove", style: .destructive, handler: { _ in
                               completed(.deleteGroup(groupId))
                           }),
                           UIAlertAction(title: "Keep", style: .default, handler: { _ in
                               completed(.markGroupAsLocalOnly(groupId))
                           })]
            return ("Warning",
                    "Group '\(groupName)' is no longer accessible. What would you like to do?",
                    actions)

        case .groupWriteDenied(let groupId, let groupName):
            let actions = [UIAlertAction(title: "Revert to original", style: .cancel, handler: { _ in
                               completed(.revertLibraryToOriginal(.group(groupId)))
                           }),
                           UIAlertAction(title: "Keep changes", style: .default, handler: { _ in
                               completed(.markChangesAsResolved(.group(groupId)))
                           })]
            return ("Warning",
                    "You can't write to group '\(groupName)' anymore. What would you like to do?",
                    actions)
        }
    }
}

extension AppCoordinator: DebugPermissionReceiver {
    func askForPermission(message: String, completed: @escaping (DebugPermissionResponse) -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?._askForPermission(message: message, completed: completed)
        }
    }

    private func _askForPermission(message: String, completed: @escaping (DebugPermissionResponse) -> Void) {
        let alert = UIAlertController(title: "Confirm action", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Allow", style: .default, handler: { _ in
            completed(.allowed)
        }))
        alert.addAction(UIAlertAction(title: "Skip", style: .default, handler: { _ in
            completed(.skipAction)
        }))
        alert.addAction(UIAlertAction(title: "Cancel sync", style: .destructive, handler: { _ in
            completed(.cancelSync)
        }))
        self.viewController?.present(alert, animated: true, completion: nil)
    }
}
