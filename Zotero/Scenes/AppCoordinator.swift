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
    func showMainScreen(isLoggedIn: Bool)
    func didRotate(to size: CGSize)
    func show(customUrl: CustomURLController.Kind, animated: Bool)
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
    private var presentedRestoredControllerWindow: UIWindow?
    private var downloadDisposeBag: DisposeBag?
    private var tmpConnectionOptions: UIScene.ConnectionOptions?
    private var tmpSession: UISceneSession?

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

    func start(options connectionOptions: UIScene.ConnectionOptions, session: UISceneSession) {
        if !self.controllers.sessionController.isInitialized {
            self.tmpConnectionOptions = connectionOptions
            self.tmpSession = session
            self.showLaunchScreen()
        } else {
            self.showMainScreen(isLogged: self.controllers.sessionController.isLoggedIn, options: connectionOptions, session: session, animated: false)
        }

        // If db needs to be wiped and this is the first start of the app, show beta alert
        if self.controllers.userControllers?.dbStorage.willPerformBetaWipe == true && self.controllers.sessionController.isLoggedIn {
            self.showBetaAlert()
        }
        if self.controllers.sessionController.isInitialized && self.controllers.debugLogging.isEnabled {
            self.setDebugWindow(visible: true)
        }

        self.controllers.debugLogging.coordinator = self
        self.controllers.crashReporter.coordinator = self
        self.controllers.translatorsAndStylesController.coordinator = self
    }

    // MARK: - Navigation

    private func showLaunchScreen() {
        guard let controller = UIStoryboard(name: "LaunchScreen", bundle: nil).instantiateInitialViewController() else { return }
        self.window?.rootViewController = controller
    }

    private func showMainScreen(isLogged: Bool, options connectionOptions: UIScene.ConnectionOptions?, session: UISceneSession?, animated: Bool) {
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

        guard let options = connectionOptions, let session = session else { return }
        self.process(connectionOptions: options, session: session)
    }

    private func process(connectionOptions: UIScene.ConnectionOptions, session: UISceneSession) {
        if let urlContext = connectionOptions.urlContexts.first, let urlController = self.controllers.userControllers?.customUrlController {
            // If scene was started from custom URL
            let sourceApp = urlContext.options.sourceApplication ?? "unknown"
            DDLogInfo("AppCoordinator: App launched by \(urlContext.url.absoluteString) from \(sourceApp)")

            if let kind = urlController.process(url: urlContext.url) {
                self.show(customUrl: kind, animated: false)
                return
            }
        }

        if let userActivity = connectionOptions.userActivities.first ?? session.stateRestorationActivity, let data = userActivity.restoredStateData {
            DDLogInfo("AppCoordinator: Restored state - \(data)")
            // If scene had state stored, restore state
            self.showRestoredState(for: data)
        }
    }

    func show(customUrl: CustomURLController.Kind, animated: Bool) {
        switch customUrl {
        case .itemDetail(let key, let library, let preselectedChildKey):
            self.showItemDetail(key: key, library: library, selectChildKey: preselectedChildKey, animated: animated)

        case .pdfReader(let attachment, let library, let page, let annotation, let parentKey, let isAvailable):
            if isAvailable {
                self.open(attachment: attachment, library: library, on: page, annotation: annotation, parentKey: parentKey, animated: animated)
                return
            }

            self.showItemDetail(key: (parentKey ?? attachment.key), library: library, selectChildKey: attachment.key, animated: animated)
            self.download(attachment: attachment, parentKey: parentKey) { [weak self] in
                self?._open(attachment: attachment, library: library, on: page, annotation: annotation, animated: true)
            }
        }
    }

    private func showItemDetail(key: String, library: Library, selectChildKey childKey: String?, animated: Bool) {
        // Dismiss presented screen if any visible
        if let mainController = self.window?.rootViewController as? MainViewController, mainController.presentedViewController != nil {
            self._showItemDetail(key: key, library: library, selectChildKey: childKey, animated: false)
            mainController.dismiss(animated: animated)
        } else {
            self._showItemDetail(key: key, library: library, selectChildKey: childKey, animated: animated)
        }
    }

    private func _showItemDetail(key: String, library: Library, selectChildKey childKey: String?, animated: Bool) {
        guard let mainController = self.window?.rootViewController as? MainViewController else { return }

        // Show "All" collection in given library/group
        if mainController.masterCoordinator?.visibleLibraryId != library.identifier ||
           (mainController.masterCoordinator?.navigationController.visibleViewController as? CollectionsViewController)?.selectedIdentifier != .custom(.all) {
            mainController.masterCoordinator?.showCollections(for: library.identifier, preselectedCollection: .custom(.all), animated: animated)
        }

        // Show item detail of given key
        if (mainController.detailCoordinator?.navigationController.visibleViewController as? ItemDetailViewController)?.key != key {
            mainController.detailCoordinator?.showItemDetail(for: .preview(key: key), library: library, scrolledToKey: childKey, animated: animated)
        }
    }

    private func open(attachment: Attachment, library: Library, on page: Int?, annotation: String?, parentKey: String?, animated: Bool) {
        #if PDFENABLED
        guard let mainController = self.window?.rootViewController as? MainViewController,
              (mainController.detailCoordinator?.navigationController.presentedViewController as? PDFReaderContainerViewController)?.key != attachment.key else { return }
        self._open(attachment: attachment, library: library, on: page, annotation: annotation, animated: animated) {
            self._showItemDetail(key: (parentKey ?? attachment.key), library: library, selectChildKey: attachment.key, animated: animated)
        }
        #endif
    }

    private func _open(attachment: Attachment, library: Library, on page: Int?, annotation: String?, animated: Bool, completion: (() -> Void)? = nil) {
        #if PDFENABLED
        switch attachment.type {
        case .file(let filename, let contentType, _, _) where contentType == "application/pdf":
            let file = Files.attachmentFile(in: library.identifier, key: attachment.key, filename: filename, contentType: contentType)
            let url = file.createUrl()

            guard let window = self.window, let detailCoordinator = (window.rootViewController as? MainViewController)?.detailCoordinator,
                  let pdfController = detailCoordinator.pdfViewController(at: url, key: attachment.key, library: library, page: page, preselectedAnnotationKey: annotation) else {
                completion?()
                return
            }
            self.show(pdfController: pdfController, in: window, animated: animated, completion: completion)

        default:
            completion?()
        }
        #endif
    }

    private func showRestoredState(for data: RestoredStateData) {
        #if PDFENABLED
        guard let window = self.window, let detailCoordinator = (window.rootViewController as? MainViewController)?.detailCoordinator,
              let (url, library) = self.loadRestoredStateData(forKey: data.key, libraryId: data.libraryId),
              let controller = detailCoordinator.pdfViewController(at: url, key: data.key, library: library, page: nil, preselectedAnnotationKey: nil) else { return }
        self.show(pdfController: controller, in: window, animated: false)
        #endif
    }

    private func loadRestoredStateData(forKey key: String, libraryId: LibraryIdentifier) -> (URL, Library)? {
        guard let dbStorage = self.controllers.userControllers?.dbStorage else { return nil }

        var url: URL?
        var library: Library?

        do {
            try dbStorage.perform(on: .main, with: { coordinator in

                let item = try coordinator.perform(request: ReadItemDbRequest(libraryId: libraryId, key: key))

                guard let attachment = AttachmentCreator.attachment(for: item, fileStorage: self.controllers.fileStorage, urlDetector: nil) else { return }

                switch attachment.type {
                case .file(let filename, let contentType, let location, _):
                    switch location {
                    case .local, .localAndChangedRemotely:
                        let file = Files.attachmentFile(in: libraryId, key: key, filename: filename, contentType: contentType)
                        url = file.createUrl()
                        library = try coordinator.perform(request: ReadLibraryDbRequest(libraryId: libraryId))

                    case .remote, .remoteMissing: break
                    }

                default: break
                }
            })
        } catch let error {
            DDLogError("AppCoordinator: can't load restored data - \(error)")
            return nil
        }

        if let url = url, let library = library {
            return (url, library)
        }
        return nil
    }

    private func show(pdfController: UIViewController, in window: UIWindow, animated: Bool, completion: (() -> Void)? = nil) {
        if animated {
            if window.rootViewController?.presentedViewController == nil {
                window.rootViewController?.present(pdfController, animated: true, completion: completion)
                return
            }

            window.rootViewController?.dismiss(animated: true, completion: {
                window.rootViewController?.present(pdfController, animated: true, completion: completion)
            })
            return
        }

        self.show(presentedViewController: pdfController, in: window) { viewController, completion in
            // Open PDF reader of given attachment
            if viewController.presentedViewController == nil {
                viewController.present(pdfController, animated: false, completion: completion)
                return
            }

            viewController.dismiss(animated: false, completion: {
                viewController.present(pdfController, animated: false, completion: completion)
            })
        }

        completion?()
    }

    /// If the app tries to present a `UIViewController` on a `UIWindow` that is being shown after app launches, there is a small delay where the underlying (presenting) `UIViewController` is visible.
    /// So the launch animation looks bad, since you can see a snapshot of previous state (PDF reader), then split view controller with collections and items and then PDF reader again. Because of that
    /// we fake it a little with this function.
    private func show(presentedViewController: UIViewController, in window: UIWindow, presentAction: (UIViewController, @escaping () -> Void) -> Void) {
        // Store original `UIViewController`
        guard let oldController = window.rootViewController else { return }

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
        self.presentedRestoredControllerWindow = tmpWindow

        window.rootViewController = oldController

        presentAction(oldController, {
            // New window is visible with a screenshot, return old view controller and present the new one
            window.rootViewController = oldController
            self.presentedRestoredControllerWindow = nil
        })
    }

    private func showBetaAlert() {
        let controller = UIAlertController(title: L10n.betaWipeTitle, message: L10n.betaWipeMessage, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: nil))
        self.window?.rootViewController?.present(controller, animated: true, completion: nil)
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

    private func download(attachment: Attachment, parentKey: String?, completion: @escaping () -> Void) {
        guard let downloader = self.controllers.userControllers?.fileDownloader else {
            completion()
            return
        }

        let disposeBag = DisposeBag()

        downloader.observable
                  .observe(on: MainScheduler.instance)
                  .subscribe(onNext: { [weak self] update in
                      guard let `self` = self, update.libraryId == attachment.libraryId && update.key == attachment.key else { return }

                      switch update.kind {
                      case .ready:
                          completion()
                          self.downloadDisposeBag = nil
                      case .cancelled, .failed:
                          self.downloadDisposeBag = nil
                      case .progress: break
                      }
                  })
                  .disposed(by: disposeBag)

        self.downloadDisposeBag = disposeBag
        downloader.downloadIfNeeded(attachment: attachment, parentKey: parentKey)
    }
}

extension AppCoordinator: AppDelegateCoordinatorDelegate {
    func showMainScreen(isLoggedIn: Bool) {
        self.showMainScreen(isLogged: isLoggedIn, options: self.tmpConnectionOptions, session: self.tmpSession, animated: true)
        self.tmpConnectionOptions = nil
        self.tmpSession = nil
    }

    func didRotate(to size: CGSize) {
        guard let window = self.debugWindow else { return }
        let xPos = window.frame.minX == AppCoordinator.debugButtonOffset ? window.frame.minX : size.width - AppCoordinator.debugButtonSize.width - AppCoordinator.debugButtonOffset
        window.frame = self.debugWindowFrame(for: size, xPos: xPos)
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
            guard let `self` = self, progress > 0 && progress < 1 else { return }

            if progressAlert == nil {
                let (controller, progress) = self.createCircularProgressAlertController(title: L10n.Settings.LogAlert.progressTitle)
                self.window?.rootViewController?.present(controller, animated: true, completion: nil)
                progressAlert = controller
                progressView = progress
            }

            progressView?.progress = CGFloat(progress)
        }

        let createCompletionAlert: (Result<(String, String?, Int), DebugLogging.Error>, [URL]?, (() -> Void)?, (() -> Void)?) -> Void = { [weak self] result, logs, retry, completion in
            if let controller = progressAlert {
                controller.presentingViewController?.dismiss(animated: true, completion: {
                    self?.showAlert(for: result, logs: logs, retry: retry, completion: completion)
                })
            } else {
                self?.showAlert(for: result, logs: logs, retry: retry, completion: completion)
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

    private func showAlert(for result: Result<(String, String?, Int), DebugLogging.Error>, logs: [URL]?, retry: (() -> Void)?, completion: (() -> Void)?) {
        switch result {
        case .success((let debugId, let customMessage, let userId)):
            self.share(debugId: debugId, customMessage: customMessage, userId: userId)
            completion?()

        case .failure(let error):
            self.show(error: error, logs: logs, retry: retry, completed: completion)
        }
    }

    private func share(debugId: String, customMessage: String?, userId: Int) {
        var actions = [UIAlertAction(title: L10n.ok, style: .cancel, handler: nil),
                       UIAlertAction(title: L10n.copy, style: .default, handler: { _ in
                          UIPasteboard.general.string = debugId
                       })]

        if userId > 0 {
            let action = UIAlertAction(title: L10n.Settings.CrashAlert.exportDb, style: .default) { [weak self] _ in
                UIPasteboard.general.string = debugId
                self?.exportDb(with: userId, completion: nil)
            }
            actions.append(action)
        }

        let message = customMessage ?? L10n.Settings.LogAlert.message(debugId)
        self.showAlert(title: L10n.Settings.LogAlert.title, message: message, actions: actions)
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

        let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(AppCoordinator.didPan))
        self.debugWindow?.addGestureRecognizer(panRecognizer)
    }

    @objc private func didPan(recognizer: UIPanGestureRecognizer) {
        guard let debugWindow = self.debugWindow, let window = self.window else { return }

        switch recognizer.state {
        case .began:
            self.originalDebugWindowFrame = debugWindow.frame

        case .changed:
            guard let originalFrame = self.originalDebugWindowFrame else { return }
            let translation = recognizer.translation(in: window)
            debugWindow.frame = originalFrame.offsetBy(dx: translation.x, dy: translation.y)

        case .cancelled, .ended, .failed:
            self.originalDebugWindowFrame = nil

            let velocity = recognizer.velocity(in: window)
            let endPosLeft = velocity.x == 0 ? (debugWindow.center.x <= (window.frame.width / 2)) : (velocity.x < 0)
            let xPos = endPosLeft ? AppCoordinator.debugButtonOffset : window.frame.width - AppCoordinator.debugButtonSize.width - AppCoordinator.debugButtonOffset
            let frame = self.debugWindowFrame(for: window.frame.size, xPos: xPos)
            let viewVelocity = abs(velocity.x / (xPos - debugWindow.frame.minX))

            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: viewVelocity, options: [.curveEaseOut], animations: {
                debugWindow.frame = frame
            }, completion: nil)

        case .possible: break
        @unknown default: break
        }
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
        let controller = SFSafariViewController(url: URL(string: "https://www.zotero.org/user/register?app=1")!)
        self.window?.rootViewController?.present(controller, animated: true, completion: nil)
    }
}

extension AppCoordinator: AppLoginCoordinatorDelegate {
    func showAbout() {
        let controller = SFSafariViewController(url: URL(string: "https://www.zotero.org/?app=1")!)
        self.window?.rootViewController?.present(controller, animated: true, completion: nil)
    }

    func showForgotPassword() {
        guard let url = URL(string: "https://www.zotero.org/user/lostpassword?app=1") else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    func dismiss() {
        self.window?.rootViewController?.dismiss(animated: true, completion: nil)
    }
}

extension AppCoordinator: CrashReporterCoordinator {
    func report(id: String, completion: @escaping () -> Void) {
        var actions = [UIAlertAction(title: L10n.ok, style: .cancel, handler: { _ in completion() }),
                       UIAlertAction(title: L10n.copy, style: .default, handler: { _ in
                          UIPasteboard.general.string = id
                          completion()
                       })]

        let userId = Defaults.shared.userId
        if userId > 0 {
            let action = UIAlertAction(title: L10n.Settings.CrashAlert.exportDb, style: .default) { [weak self] _ in
                UIPasteboard.general.string = id
                self?.exportDb(with: userId, completion: completion)
            }
            actions.append(action)
        }

        self.showAlert(title: L10n.Settings.CrashAlert.title, message: L10n.Settings.CrashAlert.message(id), actions: actions)
    }

    private func exportDb(with userId: Int, completion: (() -> Void)?) {
        let mainUrl = Files.dbFile(for: userId).createUrl()
        let bundledUrl = Files.bundledDataDbFile.createUrl()

        let controller = UIActivityViewController(activityItems: [mainUrl, bundledUrl], applicationActivities: nil)
        controller.modalPresentationStyle = .pageSheet
        controller.popoverPresentationController?.sourceView = self.viewController?.view
        controller.popoverPresentationController?.sourceRect = CGRect(x: 100, y: 100, width: 100, height: 100)
        controller.completionWithItemsHandler = { _, _, _, _ in
            completion?()
        }
        self.viewController?.present(controller, animated: true, completion: nil)
    }
}

extension AppCoordinator: TranslatorsControllerCoordinatorDelegate {
    func showBundleLoadTranslatorsError(result: @escaping (Bool) -> Void) {
        self.showAlert(title: L10n.error,
                       message: L10n.Errors.Translators.bundleLoading,
                       actions: [UIAlertAction(title: L10n.no, style: .cancel, handler: { _ in result(false) }),
                                 UIAlertAction(title: L10n.yes, style: .default, handler: { _ in result(true) })])
    }

    func showResetToBundleError() {
        self.showAlert(title: L10n.error,
                       message: L10n.Errors.Translators.bundleReset,
                       actions: [UIAlertAction(title: L10n.ok, style: .cancel, handler: nil)])
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

extension AppCoordinator: SyncRequestReceiver {
    func askToCreateZoteroDirectory(url: String, create: @escaping () -> Void, cancel: @escaping () -> Void) {
        let controller = UIAlertController(title: L10n.Settings.Sync.DirectoryNotFound.title, message: L10n.Settings.Sync.DirectoryNotFound.message(url), preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: { _ in cancel() }))
        controller.addAction(UIAlertAction(title: L10n.create, style: .default, handler: { _ in create() }))
        self.viewController?.present(controller, animated: true, completion: nil)
    }

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
