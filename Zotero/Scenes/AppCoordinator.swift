//
//  AppCoordinator.swift
//  Zotero
//
//  Created by Michal Rentka on 03/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import MessageUI
import SafariServices
import SwiftUI
import UIKit

import CocoaLumberjackSwift
import RxSwift

protocol AppDelegateCoordinatorDelegate: AnyObject {
    func showMainScreen(isLoggedIn: Bool, options: UIScene.ConnectionOptions, session: UISceneSession, animated: Bool)
    func didRotate(to size: CGSize)
    func showScreen(for urlContext: UIOpenURLContext, animated: Bool, completion: ((Bool) -> Void)?)
    func showMainScreen(with data: RestoredStateData, session: UISceneSession) -> Bool
    func continueUserActivity(_ userActivity: NSUserActivity, for sessionIdentifier: String)
}

protocol AppOnboardingCoordinatorDelegate: AnyObject {
    func showAbout()
    func presentLogin()
    func presentRegister()
}

protocol AppLoginCoordinatorDelegate: AnyObject {
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
    private var originalDebugWindowFrame: CGRect?
    private var conflictReceiverAlertController: ConflictReceiverAlertController?
    private var conflictAlertQueueController: ConflictAlertQueueController?
    var presentedRestoredControllerWindow: UIWindow?
    private var downloadDisposeBag: DisposeBag?

    private var viewController: UIViewController? {
        guard let rootViewController = window?.rootViewController else { return nil }
        let topController = rootViewController.topController
        return (topController as? MainViewController)?.viewControllers.last ?? topController
    }

    init(window: UIWindow?, controllers: Controllers) {
        self.window = window
        self.controllers = controllers
        super.init()
    }

    func start(options connectionOptions: UIScene.ConnectionOptions, session: UISceneSession) {
        if !controllers.sessionController.isInitialized {
            DDLogInfo("AppCoordinator: start while waiting for initialization")
            showLaunchScreen()
        } else {
            DDLogInfo("AppCoordinator: start logged \(controllers.sessionController.isLoggedIn ? "in" : "out")")
            showMainScreen(isLoggedIn: controllers.sessionController.isLoggedIn, options: connectionOptions, session: session, animated: false)
        }

        // If db needs to be wiped and this is the first start of the app, show beta alert
        if controllers.userControllers?.dbStorage.willPerformBetaWipe == true && controllers.sessionController.isLoggedIn {
            DDLogInfo("AppCoordinator: show beta alert")
            showBetaAlert()
        }

        if controllers.sessionController.isInitialized && controllers.debugLogging.isEnabled {
            DDLogInfo("AppCoordinator: show debug window")
            setDebugWindow(visible: true)
        }

        controllers.debugLogging.coordinator = self
        controllers.crashReporter.coordinator = self
        controllers.translatorsAndStylesController.coordinator = self

        func showLaunchScreen() {
            guard let window else { return }
            let controller = UIStoryboard(name: "LaunchScreen", bundle: nil).instantiateInitialViewController()
            window.rootViewController = controller
        }

        func showBetaAlert() {
            guard let rootViewController = window?.rootViewController else { return }
            let controller = UIAlertController(title: L10n.betaWipeTitle, message: L10n.betaWipeMessage, preferredStyle: .alert)
            controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: nil))
            rootViewController.present(controller, animated: true, completion: nil)
        }
    }

    // MARK: - Navigation
    private func showAlert(title: String, message: String, actions: [UIAlertAction]) {
        guard let viewController else { return }
        let controller = UIAlertController(title: title, message: message, preferredStyle: .alert)
        actions.forEach({ controller.addAction($0) })
        viewController.present(controller, animated: true, completion: nil)
    }

    // MARK: - Helpers
    private func debugWindowFrame(for windowSize: CGSize, xPos: CGFloat) -> CGRect {
        let yPos = windowSize.height - AppCoordinator.debugButtonSize.height - AppCoordinator.debugButtonOffset
        return CGRect(origin: CGPoint(x: xPos, y: yPos), size: AppCoordinator.debugButtonSize)
    }
}

extension AppCoordinator: AppDelegateCoordinatorDelegate {
    func showMainScreen(isLoggedIn: Bool, options: UIScene.ConnectionOptions, session: UISceneSession, animated: Bool) {
        guard let window else { return }
        let viewController: UIViewController
        var urlContext: UIOpenURLContext?
        var data: RestoredStateData?
        if !isLoggedIn {
            let controller = OnboardingViewController(size: window.frame.size, htmlConverter: controllers.htmlAttributedStringConverter)
            controller.coordinatorDelegate = self
            viewController = controller

            conflictReceiverAlertController = nil
            conflictAlertQueueController = nil
            controllers.userControllers?.syncScheduler.syncController.set(coordinator: nil)
        } else {
            (urlContext, data) = preprocess(connectionOptions: options, session: session)
            let controller = MainViewController(controllers: controllers)
            viewController = controller

            conflictReceiverAlertController = ConflictReceiverAlertController(viewController: controller)
            conflictAlertQueueController = ConflictAlertQueueController(viewController: controller)
            controllers.userControllers?.syncScheduler.syncController.set(coordinator: self)
        }

        DDLogInfo("AppCoordinator: show main screen logged \(isLoggedIn ? "in" : "out"); animated=\(animated)")
        show(viewController: viewController, in: window, animated: animated) {
            process(urlContext: urlContext, data: data, sessionIdentifier: session.persistentIdentifier)
        }

        func show(viewController: UIViewController?, in window: UIWindow, animated: Bool = false, completion: @escaping () -> Void) {
            window.rootViewController = viewController

            guard animated else {
                completion()
                return
            }

            UIView.transition(with: window, duration: 0.2, options: .transitionCrossDissolve, animations: {}, completion: { _ in completion() })
        }

        func preprocess(connectionOptions: UIScene.ConnectionOptions, session: UISceneSession) -> (UIOpenURLContext?, RestoredStateData?) {
            let urlContext = connectionOptions.urlContexts.first
            var userActivity: NSUserActivity?
            var data: RestoredStateData?
            if connectionOptions.shortcutItem?.type == NSUserActivity.mainId {
                let openItems: [OpenItem] = session.stateRestorationActivity?.restoredStateData?.openItems ?? []
                userActivity = .mainActivity(with: openItems)
                data = .myLibrary(openItems: openItems)
            } else {
                userActivity = connectionOptions.userActivities.first ?? session.stateRestorationActivity
                data = userActivity?.restoredStateData
            }
            if let data {
                // If scene had state stored, check if defaults need to be updated first
                DDLogInfo("AppCoordinator: Preprocessing restored state - \(data)")
                Defaults.shared.selectedLibraryId = data.libraryId
                Defaults.shared.selectedCollectionId = data.collectionId
                controllers.userControllers?.openItemsController.set(items: data.openItems, for: session.persistentIdentifier, validate: true)
            }
            return (urlContext, data)
        }

        func process(urlContext: UIOpenURLContext?, data: RestoredStateData?, sessionIdentifier: String) {
            if let urlContext {
                showScreen(for: urlContext, animated: false) { success in
                    guard !success else { return }
                    process(data: data, sessionIdentifier: sessionIdentifier)
                }
            } else {
                process(data: data, sessionIdentifier: sessionIdentifier)
            }

            func process(data: RestoredStateData?, sessionIdentifier: String) {
                if let data {
                    DDLogInfo("AppCoordinator: Processing restored state - \(data)")
                    // If scene had state stored, restore state
                    showRestoredState(for: data, sessionIdentifier: sessionIdentifier)
                }

                func showRestoredState(for data: RestoredStateData, sessionIdentifier: String) {
                    guard let openItemsController = controllers.userControllers?.openItemsController else { return }
                    DDLogInfo("AppCoordinator: show restored state")
                    guard let mainController = window.rootViewController as? MainViewController else {
                        DDLogWarn("AppCoordinator: show restored state aborted - invalid root view controller")
                        return
                    }
                    var collection: Collection
                    if let optionalCollection = loadRestoredStateData(libraryId: data.libraryId, collectionId: data.collectionId) {
                        DDLogInfo("AppCoordinator: show restored state using restored collection")
                        collection = optionalCollection
                        // No need to set selected collection identifier here, this happened already in show main screen / preprocess
                    } else {
                        DDLogWarn("AppCoordinator: show restored state using all items collection")
                        // Collection is missing, show all items instead
                        collection = Collection(custom: .all)
                    }
                    mainController.showItems(for: collection, in: data.libraryId)
                    guard data.restoreMostRecentlyOpenedItem else { return }
                    openItemsController.restoreMostRecentlyOpenedItem(using: self, sessionIdentifier: sessionIdentifier) { item in
                        if let item {
                            DDLogInfo("AppCoordinator: restored open item - \(item)")
                        } else {
                            DDLogInfo("AppCoordinator: no open item to restore")
                        }
                    }

                    func loadRestoredStateData(libraryId: LibraryIdentifier, collectionId: CollectionIdentifier) -> Collection? {
                        guard let dbStorage = controllers.userControllers?.dbStorage else { return nil }

                        var collection: Collection?

                        do {
                            collection = try dbStorage.perform(request: ReadCollectionDbRequest(collectionId: collectionId, libraryId: libraryId), on: .main)
                        } catch let error {
                            DDLogError("AppCoordinator: can't load restored data - \(error)")
                            return nil
                        }

                        return collection
                    }
                }
            }
        }
    }

    func didRotate(to size: CGSize) {
        guard let debugWindow else { return }
        let xPos = debugWindow.frame.minX == AppCoordinator.debugButtonOffset ? debugWindow.frame.minX : size.width - AppCoordinator.debugButtonSize.width - AppCoordinator.debugButtonOffset
        debugWindow.frame = debugWindowFrame(for: size, xPos: xPos)
    }

    func showScreen(for urlContext: UIOpenURLContext, animated: Bool, completion: ((Bool) -> Void)? = nil) {
        let sourceApp = urlContext.options.sourceApplication ?? "unknown"
        DDLogInfo("AppCoordinator: show screen for \(urlContext.url.absoluteString) from \(sourceApp)")
        guard let window, let mainController = window.rootViewController as? MainViewController else {
            DDLogWarn("AppCoordinator: show screen aborted - invalid root view controller")
            completion?(false)
            return
        }
        guard let urlController = controllers.userControllers?.customUrlController else {
            completion?(false)
            return
        }

        urlController.process(url: urlContext.url) { kind in
            guard let kind else {
                completion?(false)
                return
            }
            switch kind {
            case .itemDetail(let key, let libraryId, let preselectedChildKey):
                DDLogInfo("AppCoordinator: show screen - item detail; key=\(key); library=\(libraryId)")
                showItemDetail(in: mainController, key: key, libraryId: libraryId, selectChildKey: preselectedChildKey, animated: animated, dismissIfPresenting: true)

            case .itemReader(let presentation):
                DDLogInfo("AppCoordinator: show screen - item reader; \(presentation)")
                let key = presentation.key
                let parentKey = presentation.parentKey
                let libraryId = presentation.library.identifier
                mainController.getDetailCoordinator(for: nil, and: nil) { coordinator in
                    guard (coordinator.navigationController?.presentedViewController as? ReaderViewController)?.key != key else { return }
                    let show = {
                        coordinator.showItem(with: presentation)
                        showItemDetail(in: mainController, key: parentKey ?? key, libraryId: libraryId, selectChildKey: key, animated: false, dismissIfPresenting: false)
                    }
                    if animated {
                        show()
                    } else {
                        // When launching the app, the presentation is dispatched to the next main run loop, otherwise it fails.
                        DispatchQueue.main.async(execute: show)
                    }
                }
            }
            completion?(true)
        }

        func showItemDetail(
            in mainController: MainViewController,
            key: String,
            libraryId: LibraryIdentifier,
            selectChildKey childKey: String?,
            animated: Bool,
            dismissIfPresenting: Bool,
            completion: (() -> Void)? = nil
        ) {
            let dismissPresented = dismissIfPresenting && (mainController.presentedViewController != nil)
            let itemDetailAnimated = dismissPresented ? false : animated

            // Show "All" collection in given library/group.
            let collectionId: CollectionIdentifier = .custom(.all)
            mainController.masterCoordinator?.showCollections(for: libraryId, preselectedCollection: collectionId, animated: itemDetailAnimated)

            // Show item detail of given key.
            // If switching from another library or root view controller, while in split mode,
            // then the current detail coordinator will be replaced, so wait for the new one for the specific library and collection.
            mainController.getDetailCoordinator(for: !mainController.isCollapsed ? libraryId : nil, and: !mainController.isCollapsed ? collectionId : nil) { coordinator in
                guard let detailNavigationController = coordinator.navigationController else { return }
                if (detailNavigationController.topViewController as? ItemDetailViewController)?.key != key {
                    coordinator.showItemDetail(for: .preview(key: key), libraryId: libraryId, scrolledToKey: childKey, animated: itemDetailAnimated)
                }
                if detailNavigationController.parent == nil, mainController.isCollapsed, let navigationController = mainController.masterCoordinator?.navigationController {
                    // In collapsed mode, if the detail is not already handled by the split view controller, then it needs to be push in the stack.
                    navigationController.pushViewController(detailNavigationController, animated: itemDetailAnimated)
                }
            }

            if dismissPresented {
                // Dismiss presented screen if any visible
                mainController.dismiss(animated: animated, completion: completion)
            } else {
                completion?()
            }
        }

        func showItem(
            presentation: ItemPresentation,
            window: UIWindow,
            detailCoordinator: DetailCoordinator,
            animated: Bool,
            completion: (() -> Void)? = nil
        ) {
            guard let presenter = window.rootViewController else { return }
            show(
                viewControllerProvider: {
                    detailCoordinator.createViewController(for: presentation)
                },
                by: presenter,
                in: window,
                animated: animated,
                completion: completion
            )
        }
    }

    func showMainScreen(with data: RestoredStateData, session: UISceneSession) -> Bool {
        guard let window, let mainController = window.rootViewController as? MainViewController else { return false }
        controllers.userControllers?.openItemsController.set(items: data.openItems, for: session.persistentIdentifier, validate: true)
        mainController.dismiss(animated: false) {
            mainController.masterCoordinator?.showCollections(for: data.libraryId, preselectedCollection: data.collectionId, animated: false)
        }
        return true
    }

    func continueUserActivity(_ userActivity: NSUserActivity, for sessionIdentifier: String) {
        guard userActivity.activityType == NSUserActivity.contentContainerId, let window, let mainController = window.rootViewController as? MainViewController else { return }
        mainController.getDetailCoordinator(for: nil, and: nil) { [weak self] coordinator in
            self?.controllers.userControllers?.openItemsController.restoreMostRecentlyOpenedItem(using: coordinator, sessionIdentifier: sessionIdentifier) { item in
                if let item {
                    DDLogInfo("AppCoordinator: restored open item for continued user activity - \(item)")
                } else {
                    DDLogInfo("AppCoordinator: no open item to restore for continued user activity")
                }
            }
        }
    }
}

extension AppCoordinator: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }
}

extension AppCoordinator: DebugLoggingCoordinator {
    func createDebugAlertActions() -> ((Result<(String, String?, Int), DebugLogging.Error>, [URL]?, (() -> Void)?, (() -> Void)?) -> Void, (Double) -> Void) {
        var progressAlert: UIAlertController?
        var progressView: CircularProgressView?

        let createProgressAlert: (Double) -> Void = { [weak self] progress in
            guard let self, progress > 0 && progress < 1 else { return }

            if progressAlert == nil {
                let (controller, progress) = createCircularProgressAlertController(title: L10n.Settings.LogAlert.progressTitle)
                window?.rootViewController?.present(controller, animated: true, completion: nil)
                progressAlert = controller
                progressView = progress
            }

            progressView?.progress = CGFloat(progress)
        }

        let createCompletionAlert: (Result<(String, String?, Int), DebugLogging.Error>, [URL]?, (() -> Void)?, (() -> Void)?) -> Void = { result, logs, retry, completion in
            if let controller = progressAlert {
                controller.presentingViewController?.dismiss(animated: true, completion: {
                    showAlert(for: result, logs: logs, retry: retry, completion: completion)
                })
            } else {
                showAlert(for: result, logs: logs, retry: retry, completion: completion)
            }
        }

        return (createCompletionAlert, createProgressAlert)

        func createCircularProgressAlertController(title: String) -> (UIAlertController, CircularProgressView) {
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

        func showAlert(for result: Result<(String, String?, Int), DebugLogging.Error>, logs: [URL]?, retry: (() -> Void)?, completion: (() -> Void)?) {
            switch result {
            case .success((let debugId, let customMessage, let userId)):
                share(debugId: debugId, customMessage: customMessage, userId: userId)
                completion?()

            case .failure(let error):
                show(error: error, logs: logs, retry: retry, completed: completion)
            }

            func share(debugId: String, customMessage: String?, userId: Int) {
                let actions = [
                    UIAlertAction(title: L10n.ok, style: .cancel, handler: nil),
                    UIAlertAction(title: L10n.Settings.CrashAlert.submitForum, style: .default, handler: { _ in
                        submit(debugId: debugId)
                    }),
                    UIAlertAction(title: L10n.Settings.CrashAlert.copy, style: .default, handler: { _ in
                        UIPasteboard.general.string = debugId
                    })
                ]
                let message = customMessage ?? L10n.Settings.LogAlert.message(debugId)
                self.showAlert(title: L10n.Settings.LogAlert.title, message: message, actions: actions)
            }

            func submit(debugId: String) {
                UIPasteboard.general.string = debugId
                guard var components = URLComponents(string: "https://forums.zotero.org/post/discussion") else { return }
                components.queryItems = [URLQueryItem(name: "name", value: "iOS Debug Log: \(debugId)"), URLQueryItem(name: "body", value: "[Describe the issue you're reporting.]")]
                guard let url = components.url else { return }
                UIApplication.shared.open(url)
            }
        }
    }

    func show(error: DebugLogging.Error, logs: [URL]?, retry: (() -> Void)?, completed: (() -> Void)?) {
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
        if let retry = retry {
            actions.append(UIAlertAction(title: L10n.retry, style: .default, handler: { _ in
                retry()
            }))
        }
        if let logs = logs, let completed = completed {
            actions.append(UIAlertAction(title: L10n.Settings.sendManually, style: .default, handler: { _ in
                presentActivityViewController(with: logs, completed: completed)
            }))
        }

        showAlert(title: L10n.Errors.Logging.title, message: message, actions: actions)

        func presentActivityViewController(with items: [Any], completed: @escaping () -> Void) {
            guard let viewController else { return }

            let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
            controller.completionWithItemsHandler = { (_, _, _, _) in
                completed()
            }

            controller.popoverPresentationController?.sourceView = viewController.view
            controller.popoverPresentationController?.sourceRect = viewController.view.frame.insetBy(dx: 100, dy: 100)
            viewController.present(controller, animated: true, completion: nil)
        }
    }

    func setDebugWindow(visible: Bool) {
        if visible {
            showDebugWindow()
        } else {
            hideDebugWindow()
        }

        func showDebugWindow() {
            guard let window else { return }

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
            debugWindow.frame = debugWindowFrame(for: window.frame.size, xPos: AppCoordinator.debugButtonOffset)
            debugWindow.addSubview(view)
            // Show the window
            debugWindow.makeKeyAndVisible()
            self.debugWindow = debugWindow

            let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(AppCoordinator.didPan))
            debugWindow.addGestureRecognizer(panRecognizer)
        }

        func hideDebugWindow() {
            debugWindow = nil
        }
    }

    @objc private func didPan(recognizer: UIPanGestureRecognizer) {
        guard let debugWindow, let window else { return }

        switch recognizer.state {
        case .began:
            originalDebugWindowFrame = debugWindow.frame

        case .changed:
            guard let originalDebugWindowFrame else { return }
            let translation = recognizer.translation(in: window)
            debugWindow.frame = originalDebugWindowFrame.offsetBy(dx: translation.x, dy: translation.y)

        case .cancelled, .ended, .failed:
            originalDebugWindowFrame = nil

            let velocity = recognizer.velocity(in: window)
            let endPosLeft = velocity.x == 0 ? (debugWindow.center.x <= (window.frame.width / 2)) : (velocity.x < 0)
            let xPos = endPosLeft ? AppCoordinator.debugButtonOffset : window.frame.width - AppCoordinator.debugButtonSize.width - AppCoordinator.debugButtonOffset
            let frame = debugWindowFrame(for: window.frame.size, xPos: xPos)
            let viewVelocity = abs(velocity.x / (xPos - debugWindow.frame.minX))

            UIView.animate(
                withDuration: 0.5,
                delay: 0,
                usingSpringWithDamping: 1,
                initialSpringVelocity: viewVelocity,
                options: [.curveEaseOut],
                animations: {
                    debugWindow.frame = frame
                },
                completion: nil
            )

        case .possible:
            break

        @unknown default:
            break
        }
    }

    @objc private func stopLogging() {
        controllers.debugLogging.stop()
    }
}

extension AppCoordinator: AppOnboardingCoordinatorDelegate {
    func showAbout() {
        guard let rootViewController = window?.rootViewController else { return }
        let controller = SFSafariViewController(url: URL(string: "https://www.zotero.org/?app=1")!)
        rootViewController.present(controller, animated: true, completion: nil)
    }

    func presentLogin() {
        guard let rootViewController = window?.rootViewController else { return }
        let handler = LoginActionHandler(apiClient: controllers.apiClient, sessionController: controllers.sessionController)
        let controller = LoginViewController(viewModel: ViewModel(initialState: LoginState(), handler: handler))
        controller.coordinatorDelegate = self
        if UIDevice.current.userInterfaceIdiom == .pad {
            controller.modalPresentationStyle = .formSheet
            controller.preferredContentSize = CGSize(width: 540, height: 620)
        } else {
            controller.modalPresentationStyle = .fullScreen
        }
        controller.isModalInPresentation = false
        rootViewController.present(controller, animated: true, completion: nil)
    }

    func presentRegister() {
        guard let rootViewController = window?.rootViewController else { return }
        let controller = SFSafariViewController(url: URL(string: "https://www.zotero.org/user/register?app=1")!)
        rootViewController.present(controller, animated: true, completion: nil)
    }
}

extension AppCoordinator: AppLoginCoordinatorDelegate {
    func showForgotPassword() {
        guard let url = URL(string: "https://www.zotero.org/user/lostpassword?app=1") else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    func dismiss() {
        window?.rootViewController?.dismiss(animated: true, completion: nil)
    }
}

extension AppCoordinator: CrashReporterCoordinator {
    func report(id: String, completion: @escaping () -> Void) {
        var actions = [
            UIAlertAction(title: L10n.ok, style: .cancel, handler: { _ in completion() }),
            UIAlertAction(title: L10n.Settings.CrashAlert.submitForum, style: .default, handler: { _ in
                UIPasteboard.general.string = id
                submit(reportId: id, completion: completion)
            })
        ]

        let userId = Defaults.shared.userId
        if userId > 0 {
            let action = UIAlertAction(title: L10n.Settings.CrashAlert.exportDb, style: .default) { [weak self] _ in
                UIPasteboard.general.string = id
                self?.exportDb(with: userId, completion: completion)
            }
            actions.append(action)
        }

        showAlert(title: L10n.Settings.CrashAlert.title, message: L10n.Settings.CrashAlert.message(id), actions: actions)

        func submit(reportId: String, completion: @escaping () -> Void) {
            guard var components = URLComponents(string: "https://forums.zotero.org/post/discussion") else { return }
            components.queryItems = [URLQueryItem(name: "name", value: "iOS Crash Report: \(reportId)"), URLQueryItem(name: "body", value: "[Describe what you were doing when the crash occurred.]")]
            guard let url = components.url else { return }
            UIApplication.shared.open(url)
            completion()
        }
    }

    private func exportDb(with userId: Int, completion: (() -> Void)?) {
        guard let viewController else { return }
        let mainUrl = Files.dbFile(for: userId).createUrl()
        let bundledUrl = Files.bundledDataDbFile.createUrl()

        let controller = UIActivityViewController(activityItems: [mainUrl, bundledUrl], applicationActivities: nil)
        controller.modalPresentationStyle = .pageSheet
        controller.popoverPresentationController?.sourceView = viewController.view
        controller.popoverPresentationController?.sourceRect = CGRect(x: 100, y: 100, width: 100, height: 100)
        controller.completionWithItemsHandler = { _, _, _, _ in
            completion?()
        }
        viewController.present(controller, animated: true, completion: nil)
    }
}

extension AppCoordinator: TranslatorsControllerCoordinatorDelegate {
    func showBundleLoadTranslatorsError(result: @escaping (Bool) -> Void) {
        showAlert(
            title: L10n.error,
            message: L10n.Errors.Translators.bundleLoading,
            actions: [UIAlertAction(title: L10n.no, style: .cancel, handler: { _ in result(false) }), UIAlertAction(title: L10n.yes, style: .default, handler: { _ in result(true) })]
        )
    }

    func showResetToBundleError() {
        showAlert(title: L10n.error, message: L10n.Errors.Translators.bundleReset, actions: [UIAlertAction(title: L10n.ok, style: .cancel, handler: nil)])
    }
}

extension AppCoordinator: ConflictReceiver {
    func resolve(conflict: Conflict, completed: @escaping (ConflictResolution?) -> Void) {
        DispatchQueue.main.async {
            _resolve(conflict: conflict, completed: completed)
        }

        func _resolve(conflict: Conflict, completed: @escaping (ConflictResolution?) -> Void) {
            switch conflict {
            case .objectsRemovedRemotely(let libraryId, let collections, let items, let searches, let tags):
                guard let controller = conflictReceiverAlertController else {
                    completed(
                        .remoteDeletionOfActiveObject(
                            libraryId: libraryId,
                            toDeleteCollections: collections,
                            toRestoreCollections: [],
                            toDeleteItems: items,
                            toRestoreItems: [],
                            searches: searches,
                            tags: tags
                        )
                    )
                    return
                }

                let handler = ActiveObjectDeletedConflictReceiverHandler(
                    collections: collections,
                    items: items,
                    libraryId: libraryId
                ) { toDeleteCollections, toRestoreCollections, toDeleteItems, toRestoreItems in
                    completed(
                        .remoteDeletionOfActiveObject(
                            libraryId: libraryId,
                            toDeleteCollections: toDeleteCollections,
                            toRestoreCollections: toRestoreCollections,
                            toDeleteItems: toDeleteItems,
                            toRestoreItems: toRestoreItems,
                            searches: searches,
                            tags: tags
                        )
                    )
                }
                controller.start(with: handler)

            case .removedItemsHaveLocalChanges(let items, let libraryId):
                guard let controller = conflictAlertQueueController else {
                    completed(.remoteDeletionOfChangedItem(libraryId: libraryId, toDelete: items.map({ $0.0 }), toRestore: []))
                    return
                }

                let handler = ChangedItemsDeletedAlertQueueHandler(items: items) { toDelete, toRestore in
                    completed(.remoteDeletionOfChangedItem(libraryId: libraryId, toDelete: toDelete, toRestore: toRestore))
                }
                controller.start(with: handler)

            case .groupRemoved, .groupMetadataWriteDenied, .groupFileWriteDenied:
                presentAlert(for: conflict, completed: completed)
            }

            func presentAlert(for conflict: Conflict, completed: @escaping (ConflictResolution?) -> Void) {
                guard let viewController else { return }
                let (title, message, actions) = createAlert(for: conflict, completed: completed)

                let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                actions.forEach { action in
                    alert.addAction(action)
                }
                viewController.present(alert, animated: true, completion: nil)

                func createAlert(for conflict: Conflict, completed: @escaping (ConflictResolution?) -> Void) -> (title: String, message: String, actions: [UIAlertAction]) {
                    switch conflict {
                    case .groupRemoved(let groupId, let groupName):
                        let actions = [UIAlertAction(title: L10n.remove, style: .destructive, handler: { _ in
                            completed(.deleteGroup(groupId))
                        }),
                                       UIAlertAction(title: L10n.keep, style: .default, handler: { _ in
                            completed(.markGroupAsLocalOnly(groupId))
                        })]
                        return (L10n.warning, L10n.Errors.Sync.groupRemoved(groupName), actions)

                    case .groupMetadataWriteDenied(let groupId, let groupName):
                        let actions = [UIAlertAction(title: L10n.Errors.Sync.revertToOriginal, style: .cancel, handler: { _ in
                            completed(.revertGroupChanges(.group(groupId)))
                        }),
                                       UIAlertAction(title: L10n.Errors.Sync.skipGroup, style: .default, handler: { _ in
                            completed(.skipGroup(.group(groupId)))
                        })]
                        return (L10n.warning, L10n.Errors.Sync.metadataWriteDenied(groupName), actions)

                    case .groupFileWriteDenied(let groupId, let groupName):
                        guard let webDavController = controllers.userControllers?.webDavController else { return ("", "", []) }

                        let domainName: String
                        if !webDavController.sessionStorage.isEnabled {
                            domainName = "zotero.org"
                        } else {
                            let url = URL(string: webDavController.sessionStorage.url)
                            domainName = url?.host() ?? ""
                        }

                        let actions = [UIAlertAction(title: L10n.Errors.Sync.resetGroupFiles, style: .cancel, handler: { _ in
                            completed(.revertGroupFiles(.group(groupId)))
                        }),
                                       UIAlertAction(title: L10n.Errors.Sync.skipGroup, style: .default, handler: { _ in
                            completed(.skipGroup(.group(groupId)))
                        })]
                        return (L10n.warning, L10n.Errors.Sync.fileWriteDenied(groupName, domainName), actions)

                    case .objectsRemovedRemotely, .removedItemsHaveLocalChanges:
                        return ("", "", [])
                    }
                }
            }
        }
    }
}

extension AppCoordinator: SyncRequestReceiver {
    func askToCreateZoteroDirectory(url: String, create: @escaping () -> Void, cancel: @escaping () -> Void) {
        guard let viewController else { return }
        let controller = UIAlertController(title: L10n.Settings.Sync.DirectoryNotFound.title, message: L10n.Settings.Sync.DirectoryNotFound.message(url), preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: { _ in cancel() }))
        controller.addAction(UIAlertAction(title: L10n.create, style: .default, handler: { _ in create() }))
        viewController.present(controller, animated: true, completion: nil)
    }

    func askForPermission(message: String, completed: @escaping (DebugPermissionResponse) -> Void) {
        DispatchQueue.main.async {
            _askForPermission(message: message, completed: completed)
        }

        func _askForPermission(message: String, completed: @escaping (DebugPermissionResponse) -> Void) {
            guard let viewController else { return }
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
            viewController.present(alert, animated: true, completion: nil)
        }
    }
}

extension AppCoordinator: OpenItemsPresenter {
    func showItem(with presentation: ItemPresentation?) {
        guard let presentation, let window, let mainController = window.rootViewController as? MainViewController else { return }
        mainController.getDetailCoordinator(for: nil, and: nil) { [weak self] coordinator in
            guard let self else { return }
            show(
                viewControllerProvider: {
                    return coordinator.createViewController(for: presentation)
                },
                by: mainController,
                in: window,
                animated: false
            )
        }
    }
}

extension AppCoordinator: InstantPresenter {}
