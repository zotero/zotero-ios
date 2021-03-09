//
//  AppCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 03/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import MessageUI
import SwiftUI
import UIKit

protocol AppDelegateCoordinatorDelegate: class {
    func showMainScreen(isLoggedIn: Bool)
    func show(error: Error)
    func didRotate(to size: CGSize)
}

protocol AppOnboardingCoordinatorDelegate: class {
    func presentLogin()
    func presentRegister()
}

protocol AppLoginCoordinatorDelegate: class {
    func dismiss()
    func showForgotPassword()
}

final class AppCoordinator: NSObject {
    private typealias Action = (UIViewController) -> Void

    private static let debugButtonSize = CGSize(width: 60, height: 60)
    private static let debugButtonOffset: CGFloat = 50
    private let controllers: Controllers

    private weak var window: UIWindow?
    private var debugWindow: UIWindow?
    private var conflictReceiverAlertController: ConflictReceiverAlertController?
    private var conflictAlertQueueController: ConflictAlertQueueController?

    private var viewController: UIViewController? {
        guard let viewController = self.window?.rootViewController else { return nil }
        let topController = viewController.topController
        return (topController as? MainViewController)?.viewControllers.last ?? topController
    }

    init(window: UIWindow?, controllers: Controllers) {
        self.window = window
        self.controllers = controllers
        super.init()
    }

    func start() {
        self.showMainScreen(isLogged: self.controllers.sessionController.isLoggedIn, animated: false)
        if let error = self.controllers.userControllerError {
            self.show(error: error)
        }

        if self.controllers.debugLogging.isEnabled {
            self.setDebugWindow(visible: true)
        }

        self.controllers.debugLogging.coordinator = self
        self.controllers.crashReporter.coordinator = self
        self.controllers.translatorsController.coordinator = self
    }

    // MARK: - Navigation

    private func showMainScreen(isLogged: Bool, animated: Bool) {
        guard let window = self.window else { return }

        let viewController: UIViewController
        if !isLogged {
            let controller = OnboardingViewController(size: window.frame.size, htmlConverter: self.controllers.htmlAttributedStringConverter)
            controller.coordinatorDelegate = self
            viewController = controller

            self.conflictReceiverAlertController = nil
            self.conflictAlertQueueController = nil
            self.controllers.userControllers?.syncScheduler.syncController.set(coordinator: nil)
        } else {
            let controller = MainViewController(controllers: self.controllers)
            viewController = controller

            self.conflictReceiverAlertController = ConflictReceiverAlertController(viewController: controller)
            self.conflictAlertQueueController = ConflictAlertQueueController(viewController: controller)
            self.controllers.userControllers?.syncScheduler.syncController.set(coordinator: self)
        }

        self.show(viewController: viewController, in: window, animated: animated)
    }

    private func show(viewController: UIViewController?, in window: UIWindow, animated: Bool = false) {
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

    // MARK: - Helpers

    private func debugWindowFrame(for windowSize: CGSize, xPos: CGFloat) -> CGRect {
        let yPos = windowSize.height - AppCoordinator.debugButtonSize.height - AppCoordinator.debugButtonOffset
        return CGRect(origin: CGPoint(x: xPos, y: yPos), size: AppCoordinator.debugButtonSize)
    }
}

extension AppCoordinator: AppDelegateCoordinatorDelegate {
    func showMainScreen(isLoggedIn: Bool) {
        self.showMainScreen(isLogged: isLoggedIn, animated: true)
    }

    func show(error: Error) {
        let controller = UIAlertController(title: L10n.error, message: L10n.Errors.dbFailure, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: nil))
        controller.addAction(UIAlertAction(title: L10n.report, style: .default, handler: { [weak self] _ in
            self?.report(error: error)
        }))
        self.viewController?.present(controller, animated: true, completion: nil)
    }

    private func report(error: Error) {
        guard MFMailComposeViewController.canSendMail() else {
            return
        }

        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = self
        controller.setToRecipients(["michalrentka@gmail.com"])
        controller.setMessageBody("Error:\n\(error)", isHTML: false)
        self.viewController?.present(controller, animated: true, completion: nil)
    }

    func didRotate(to size: CGSize) {
        guard let window = self.debugWindow else { return }
        window.frame = self.debugWindowFrame(for: size, xPos: window.frame.minX)
    }
}

extension AppCoordinator: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }
}

extension AppCoordinator: DebugLoggingCoordinator {
    func createDebugAlertActions() -> ((Result<String, DebugLogging.Error>, [URL]?, (() -> Void)?) -> Void, (Float) -> Void) {
        var progressAlert: UIAlertController?
        var progressView: CircularProgressView?

        let createProgressAlert: (Float) -> Void = { [weak self] progress in
            guard let `self` = self, progress > 0 else { return }

            if progressAlert == nil {
                let (controller, progress) = self.createCircularProgressAlertController(title: L10n.Settings.LogAlert.progressTitle)
                self.window?.rootViewController?.present(controller, animated: true, completion: nil)
                progressAlert = controller
                progressView = progress
            }

            progressView?.progress = CGFloat(progress)
        }

        let createCompletionAlert: (Result<String, DebugLogging.Error>, [URL]?, (() -> Void)?) -> Void = { [weak self] result, logs, completion in
            if let controller = progressAlert {
                controller.presentingViewController?.dismiss(animated: true, completion: {
                    self?.showAlert(for: result, logs: logs, completion: completion)
                })
            } else {
                self?.showAlert(for: result, logs: logs, completion: completion)
            }
        }

        return (createCompletionAlert, createProgressAlert)
    }

    private func createCircularProgressAlertController(title: String) -> (UIAlertController, CircularProgressView) {
        let progressView = CircularProgressView(size: 40, lineWidth: 3)
        progressView.translatesAutoresizingMaskIntoConstraints = false

        let controller = UIAlertController(title: title, message: "\n\n\n", preferredStyle: .alert)
        controller.view.addSubview(progressView)

        NSLayoutConstraint.activate([
            controller.view.bottomAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 20),
            progressView.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor)
        ])

        return (controller, progressView)
    }

    private func showAlert(for result: Result<String, DebugLogging.Error>, logs: [URL]?, completion: (() -> Void)?) {
        switch result {
        case .success(let debugId):
            self.share(debugId: debugId)
            completion?()

        case .failure(let error):
            self.show(error: error, logs: logs, completed: completion)
        }
    }

    private func share(debugId: String) {
        let actions = [UIAlertAction(title: L10n.ok, style: .cancel, handler: nil),
                       UIAlertAction(title: L10n.copy, style: .default, handler: { _ in
                          UIPasteboard.general.string = debugId
                       })]
        self.showAlert(title: L10n.Settings.LogAlert.title, message: L10n.Settings.LogAlert.message(debugId), actions: actions)
    }

    func show(error: DebugLogging.Error, logs: [URL]?, completed: (() -> Void)?) {
        let message: String
        switch error {
        case .start:
            message = L10n.Errors.Logging.start
        case .contentReading, .cantCreateData:
            message = L10n.Errors.Logging.contentReading
        case .noLogsRecorded:
            message = L10n.Errors.Logging.noLogsRecorded
        case .upload:
            message = L10n.Errors.Logging.upload
        case .responseParsing:
            message = L10n.Errors.Logging.responseParsing
        }

        var actions = [UIAlertAction(title: L10n.ok, style: .cancel, handler: { _ in
            completed?()
        })]
        if let logs = logs, let completed = completed {
            actions.append(UIAlertAction(title: L10n.Settings.sendManually, style: .default, handler: { [weak self] _ in
                self?.presentActivityViewController(with: logs, completed: completed)
            }))
        }

        self.showAlert(title: L10n.Errors.Logging.title, message: message, actions: actions)
    }

    func setDebugWindow(visible: Bool) {
        if visible {
            self.showDebugWindow()
        } else {
            self.hideDebugWindow()
        }
    }

    private func showDebugWindow() {
        guard let window = self.window else { return }

        // Create button
        let view = UIButton(frame: CGRect(origin: CGPoint(), size: AppCoordinator.debugButtonSize))
        view.setImage(UIImage(systemName: "square.fill"), for: .normal)
        view.addTarget(self, action: #selector(AppCoordinator.stopLogging), for: .touchUpInside)
        view.tintColor = .white
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.backgroundColor = Asset.Colors.zoteroBlueWithDarkMode.color
        view.layer.cornerRadius = AppCoordinator.debugButtonSize.height / 2
        view.layer.masksToBounds = true
        // Create window with button
        let debugWindow = UIWindow()
        debugWindow.backgroundColor = .clear
        debugWindow.windowScene = window.windowScene
        debugWindow.frame = self.debugWindowFrame(for: window.frame.size, xPos: AppCoordinator.debugButtonOffset)
        debugWindow.addSubview(view)
        // Show the window
        debugWindow.makeKeyAndVisible()
        self.debugWindow = debugWindow
    }

    @objc private func stopLogging() {
        self.controllers.debugLogging.stop()
    }

    private func hideDebugWindow() {
        self.debugWindow = nil
    }
}

extension AppCoordinator: AppOnboardingCoordinatorDelegate {
    func presentLogin() {
        let handler = LoginActionHandler(apiClient: self.controllers.apiClient, sessionController: self.controllers.sessionController)
        let controller = LoginViewController(viewModel: ViewModel(initialState: LoginState(), handler: handler))
        controller.coordinatorDelegate = self
        if UIDevice.current.userInterfaceIdiom == .pad {
            controller.modalPresentationStyle = .formSheet
            controller.preferredContentSize = CGSize(width: 540, height: 620)
        } else {
            controller.modalPresentationStyle = .fullScreen
        }
        controller.isModalInPresentation = false
        self.window?.rootViewController?.present(controller, animated: true, completion: nil)
    }

    func presentRegister() {
        let view = RegisterView()
        let controller = UIHostingController(rootView: view)
        self.window?.rootViewController?.present(controller, animated: true, completion: nil)
    }
}

extension AppCoordinator: AppLoginCoordinatorDelegate {
    func showForgotPassword() {
        guard let url = URL(string: "https://www.zotero.org/user/lostpassword") else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    func dismiss() {
        self.window?.rootViewController?.dismiss(animated: true, completion: nil)
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
        switch conflict {
        case .objectsRemovedRemotely(let libraryId, let collections, let items, let searches, let tags):
            guard let controller = self.conflictReceiverAlertController else {
                completed(.remoteDeletionOfActiveObject(libraryId: libraryId, toDeleteCollections: collections, toRestoreCollections: [],
                                                        toDeleteItems: items, toRestoreItems: [], searches: searches, tags: tags))
                return
            }

            let handler = ActiveObjectDeletedConflictReceiverHandler(collections: collections, items: items, libraryId: libraryId) { toDeleteCollections, toRestoreCollections, toDeleteItems, toRestoreItems in
                completed(.remoteDeletionOfActiveObject(libraryId: libraryId, toDeleteCollections: toDeleteCollections, toRestoreCollections: toRestoreCollections,
                                                        toDeleteItems: toDeleteItems, toRestoreItems: toRestoreItems, searches: searches, tags: tags))
            }
            controller.start(with: handler)

        case .removedItemsHaveLocalChanges(let items, let libraryId):
            guard let controller = self.conflictAlertQueueController else {
                completed(.remoteDeletionOfChangedItem(libraryId: libraryId, toDelete: items.map({ $0.0 }), toRestore: []))
                return
            }

            let handler = ChangedItemsDeletedAlertQueueHandler(items: items) { toDelete, toRestore in
                completed(.remoteDeletionOfChangedItem(libraryId: libraryId, toDelete: toDelete, toRestore: toRestore))
            }
            controller.start(with: handler)

        case .groupRemoved, .groupWriteDenied:
            self.presentAlert(for: conflict, completed: completed)
        }
    }

    private func presentAlert(for conflict: Conflict, completed: @escaping (ConflictResolution?) -> Void) {
        let (title, message, actions) = self.createAlert(for: conflict, completed: completed)

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        actions.forEach { action in
            alert.addAction(action)
        }
        self.viewController?.present(alert, animated: true, completion: nil)
    }

    private func createAlert(for conflict: Conflict, completed: @escaping (ConflictResolution?) -> Void) -> (title: String, message: String, actions: [UIAlertAction]) {
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
                               completed(.revertGroupChanges(.group(groupId)))
                           }),
                           UIAlertAction(title: "Keep changes", style: .default, handler: { _ in
                               completed(.keepGroupChanges(.group(groupId)))
                           })]
            return ("Warning",
                    "You can't write to group '\(groupName)' anymore. What would you like to do?",
                    actions)

        case .objectsRemovedRemotely, .removedItemsHaveLocalChanges:
            return ("", "", [])
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
