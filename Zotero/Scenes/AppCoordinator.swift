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
    var presentedRestoredControllerWindow: UIWindow?
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
            DDLogInfo("AppCoordinator: start while waiting for initialization")
            self.tmpConnectionOptions = connectionOptions
            self.tmpSession = session
            self.showLaunchScreen()
        } else {
            DDLogInfo("AppCoordinator: start logged \(self.controllers.sessionController.isLoggedIn ? "in" : "out")")
            self.showMainScreen(isLogged: self.controllers.sessionController.isLoggedIn, options: connectionOptions, session: session, animated: false)
        }

        // If db needs to be wiped and this is the first start of the app, show beta alert
        if self.controllers.userControllers?.dbStorage.willPerformBetaWipe == true && self.controllers.sessionController.isLoggedIn {
            DDLogInfo("AppCoordinator: show beta alert")
            showBetaAlert()
        }

        if self.controllers.sessionController.isInitialized && self.controllers.debugLogging.isEnabled {
            DDLogInfo("AppCoordinator: show debug window")
            self.setDebugWindow(visible: true)
        }

        self.controllers.debugLogging.coordinator = self
        self.controllers.crashReporter.coordinator = self
        self.controllers.translatorsAndStylesController.coordinator = self

        func showBetaAlert() {
            let controller = UIAlertController(title: L10n.betaWipeTitle, message: L10n.betaWipeMessage, preferredStyle: .alert)
            controller.addAction(UIAlertAction(title: L10n.ok, style: .cancel, handler: nil))
            self.window?.rootViewController?.present(controller, animated: true, completion: nil)
        }
    }

    // MARK: - Navigation

    private func showLaunchScreen() {
        guard let controller = UIStoryboard(name: "LaunchScreen", bundle: nil).instantiateInitialViewController() else { return }
        self.window?.rootViewController = controller
    }

    private func showMainScreen(isLogged: Bool, options connectionOptions: UIScene.ConnectionOptions?, session: UISceneSession?, animated: Bool) {
        guard let window else { return }

        let viewController: UIViewController
        var urlContext: UIOpenURLContext?
        var data: RestoredStateData?
        if !isLogged {
            let controller = OnboardingViewController(size: window.frame.size, htmlConverter: self.controllers.htmlAttributedStringConverter)
            controller.coordinatorDelegate = self
            viewController = controller

            self.conflictReceiverAlertController = nil
            self.conflictAlertQueueController = nil
            self.controllers.userControllers?.syncScheduler.syncController.set(coordinator: nil)
        } else {
            (urlContext, data) = preprocess(connectionOptions: connectionOptions, session: session)
            let controller = MainViewController(controllers: self.controllers)
            viewController = controller

            self.conflictReceiverAlertController = ConflictReceiverAlertController(viewController: controller)
            self.conflictAlertQueueController = ConflictAlertQueueController(viewController: controller)
            self.controllers.userControllers?.syncScheduler.syncController.set(coordinator: self)
        }

        DDLogInfo("AppCoordinator: show main screen logged \(isLogged ? "in" : "out"); animated=\(animated)")
        show(viewController: viewController, in: window, animated: animated) {
            process(urlContext: urlContext, data: data)
        }

        func show(viewController: UIViewController?, in window: UIWindow, animated: Bool = false, completion: @escaping () -> Void) {
            window.rootViewController = viewController

            guard animated else {
                completion()
                return
            }

            UIView.transition(with: window, duration: 0.2, options: .transitionCrossDissolve, animations: {}, completion: { _ in completion() })
        }

        func preprocess(connectionOptions: UIScene.ConnectionOptions?, session: UISceneSession?) -> (UIOpenURLContext?, RestoredStateData?) {
            let urlContext = connectionOptions?.urlContexts.first
            let userActivity = connectionOptions?.userActivities.first ?? session?.stateRestorationActivity
            let data = userActivity?.restoredStateData
            if let data {
                // If scene had state stored, check if defaults need to be updated first
                DDLogInfo("AppCoordinator: Preprocessing restored state - \(data)")
                Defaults.shared.selectedLibrary = data.libraryId
                Defaults.shared.selectedCollectionId = data.collectionId
                controllers.userControllers?.openItemsController.setItems(data.openItems)
            }
            return (urlContext, data)
        }

        func process(urlContext: UIOpenURLContext?, data: RestoredStateData?) {
            if let urlContext, let urlController = self.controllers.userControllers?.customUrlController {
                // If scene was started from custom URL
                let sourceApp = urlContext.options.sourceApplication ?? "unknown"
                DDLogInfo("AppCoordinator: App launched by \(urlContext.url.absoluteString) from \(sourceApp)")

                if let kind = urlController.process(url: urlContext.url) {
                    self.show(customUrl: kind, animated: false)
                    return
                }
            }

            if let data, data.restoreMostRecentlyOpenedItem {
                DDLogInfo("AppCoordinator: Processing restored state - \(data)")
                // If scene had state stored, restore state
                showRestoredState(for: data)
            }

            func showRestoredState(for data: RestoredStateData) {
                guard let openItemsController = controllers.userControllers?.openItemsController else { return }
                DDLogInfo("AppCoordinator: show restored state")
                guard let mainController = self.window?.rootViewController as? MainViewController else {
                    DDLogWarn("AppCoordinator: show restored state aborted - invalid root view controller")
                    return
                }
                guard let (library, optionalCollection) = loadRestoredStateData(libraryId: data.libraryId, collectionId: data.collectionId) else {
                    DDLogWarn("AppCoordinator: show restored state aborted - invalid restored state data")
                    return
                }
                var collection: Collection
                if let optionalCollection {
                    DDLogInfo("AppCoordinator: show restored state using restored collection")
                    collection = optionalCollection
                    // No need to set selected collection identifier here, this happened already in show main screen / preprocess
                } else {
                    DDLogWarn("AppCoordinator: show restored state using all items collection")
                    // Collection is missing, show all items instead
                    collection = Collection(custom: .all)
                }
                mainController.showItems(for: collection, in: library)
                openItemsController.restoreMostRecentlyOpenedItem(using: self)

                func loadRestoredStateData(libraryId: LibraryIdentifier, collectionId: CollectionIdentifier) -> (Library, Collection?)? {
                    guard let dbStorage = self.controllers.userControllers?.dbStorage else { return nil }

                    var library: Library?
                    var collection: Collection?

                    do {
                        try dbStorage.perform(on: .main, with: { coordinator in
                            let (_collection, _library) = try coordinator.perform(request: ReadCollectionAndLibraryDbRequest(collectionId: collectionId, libraryId: libraryId))
                            collection = _collection
                            library = _library
                        })
                    } catch let error {
                        DDLogError("AppCoordinator: can't load restored data - \(error)")
                        return nil
                    }

                    if let library = library {
                        return (library, collection)
                    }
                    return nil
                }
            }
        }
    }

    func show(customUrl: CustomURLController.Kind, animated: Bool) {
        guard let window, let mainController = window.rootViewController as? MainViewController else {
            DDLogWarn("AppCoordinator: show custom url aborted - invalid root view controller")
            return
        }

        switch customUrl {
        case .itemDetail(let key, let library, let preselectedChildKey):
            DDLogInfo("AppCoordinator: show custom url - item detail; key=\(key); library=\(library.identifier)")
            showItemDetail(in: mainController, key: key, library: library, selectChildKey: preselectedChildKey, animated: animated, dismissIfPresenting: true)

        case .pdfReader(let attachment, let library, let page, let annotation, let parentKey, let isAvailable):
            let message = DDLogMessageFormat(
                stringLiteral:
                    "AppCoordinator: show custom url - pdf reader; key=\(attachment.key); library=\(library.identifier);" +
                " page=\(page.flatMap(String.init) ?? "nil"); annotation=\(annotation ?? "nil"); parentKey=\(parentKey ?? "nil")"
            )
            DDLogInfo(message)
            mainController.getDetailCoordinator { coordinator in
                if isAvailable {
                    guard (coordinator.navigationController?.presentedViewController as? PDFReaderViewController)?.key != attachment.key else { return }
                    open(attachment: attachment, library: library, on: page, annotation: annotation, window: window, detailCoordinator: coordinator, animated: animated) {
                        showItemDetail(in: mainController, key: (parentKey ?? attachment.key), library: library, selectChildKey: attachment.key, animated: animated, dismissIfPresenting: false)
                    }
                } else {
                    showItemDetail(in: mainController, key: (parentKey ?? attachment.key), library: library, selectChildKey: attachment.key, animated: animated, dismissIfPresenting: true)
                    download(attachment: attachment, parentKey: parentKey) {
                        open(attachment: attachment, library: library, on: page, annotation: annotation, window: window, detailCoordinator: coordinator, animated: true)
                    }
                }
            }
        }

        func showItemDetail(in mainController: MainViewController, key: String, library: Library, selectChildKey childKey: String?, animated: Bool, dismissIfPresenting: Bool) {
            let dismissPresented = dismissIfPresenting && (mainController.presentedViewController != nil)
            let itemDetailAnimated = dismissPresented ? false : animated

            // Show "All" collection in given library/group
            if let coordinator = mainController.masterCoordinator,
               coordinator.visibleLibraryId != library.identifier ||
                (coordinator.navigationController?.visibleViewController as? CollectionsViewController)?.selectedIdentifier != .custom(.all) {
                coordinator.showCollections(for: library.identifier, preselectedCollection: .custom(.all), animated: itemDetailAnimated)
            }

            // Show item detail of given key
            mainController.getDetailCoordinator { coordinator in
                if (coordinator.navigationController?.visibleViewController as? ItemDetailViewController)?.key != key {
                    coordinator.showItemDetail(for: .preview(key: key), library: library, scrolledToKey: childKey, animated: itemDetailAnimated)
                }
            }

            if dismissPresented {
                // Dismiss presented screen if any visible
                mainController.dismiss(animated: animated)
            }
        }

        func download(attachment: Attachment, parentKey: String?, completion: @escaping () -> Void) {
            guard let downloader = self.controllers.userControllers?.fileDownloader else {
                completion()
                return
            }

            let disposeBag = DisposeBag()

            downloader.observable
                .observe(on: MainScheduler.instance)
                .subscribe(onNext: { [weak self] update in
                    guard let self, update.libraryId == attachment.libraryId && update.key == attachment.key else { return }

                    switch update.kind {
                    case .ready:
                        completion()
                        self.downloadDisposeBag = nil

                    case .cancelled, .failed:
                        self.downloadDisposeBag = nil

                    case .progress:
                        break
                    }
                })
                .disposed(by: disposeBag)

            self.downloadDisposeBag = disposeBag
            downloader.downloadIfNeeded(attachment: attachment, parentKey: parentKey)
        }

        func open(
            attachment: Attachment,
            library: Library,
            on page: Int?,
            annotation: String?,
            window: UIWindow,
            detailCoordinator: DetailCoordinator,
            animated: Bool,
            completion: (() -> Void)? = nil
        ) {
            switch attachment.type {
            case .file(let filename, let contentType, _, _) where contentType == "application/pdf":
                guard let presenter = window.rootViewController else { return }
                let file = Files.attachmentFile(in: library.identifier, key: attachment.key, filename: filename, contentType: contentType)
                let url = file.createUrl()
                let controller = detailCoordinator.createPDFController(key: attachment.key, library: library, url: url, page: page, preselectedAnnotationKey: annotation)
                self.show(controller: controller, by: presenter, in: window, animated: animated, completion: completion)

            default:
                completion?()
            }
        }
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
        self.showMainScreen(isLogged: isLoggedIn, options: self.tmpConnectionOptions, session: self.tmpSession, animated: false)
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
            guard let self, progress > 0 && progress < 1 else { return }

            if progressAlert == nil {
                let (controller, progress) = createCircularProgressAlertController(title: L10n.Settings.LogAlert.progressTitle)
                self.window?.rootViewController?.present(controller, animated: true, completion: nil)
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
                self.show(error: error, logs: logs, retry: retry, completed: completion)
            }

            func share(debugId: String, customMessage: String?, userId: Int) {
                var actions = [
                    UIAlertAction(title: L10n.ok, style: .cancel, handler: nil),
                    UIAlertAction(title: L10n.copy, style: .default, handler: { _ in
                        UIPasteboard.general.string = debugId
                    })
                ]

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

        self.showAlert(title: L10n.Errors.Logging.title, message: message, actions: actions)

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
            debugWindow.frame = self.debugWindowFrame(for: window.frame.size, xPos: AppCoordinator.debugButtonOffset)
            debugWindow.addSubview(view)
            // Show the window
            debugWindow.makeKeyAndVisible()
            self.debugWindow = debugWindow

            let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(AppCoordinator.didPan))
            self.debugWindow?.addGestureRecognizer(panRecognizer)
        }

        func hideDebugWindow() {
            self.debugWindow = nil
        }
    }

    @objc private func didPan(recognizer: UIPanGestureRecognizer) {
        guard let debugWindow, let window else { return }

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
        self.controllers.debugLogging.stop()
    }
}

extension AppCoordinator: AppOnboardingCoordinatorDelegate {
    func showAbout() {
        let controller = SFSafariViewController(url: URL(string: "https://www.zotero.org/?app=1")!)
        self.window?.rootViewController?.present(controller, animated: true, completion: nil)
    }

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
        var actions = [
            UIAlertAction(title: L10n.ok, style: .cancel, handler: { _ in completion() }),
            UIAlertAction(title: L10n.Settings.CrashAlert.copyId, style: .default, handler: { _ in
                UIPasteboard.general.string = id
                completion()
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
        self.showAlert(
            title: L10n.error,
            message: L10n.Errors.Translators.bundleLoading,
            actions: [UIAlertAction(title: L10n.no, style: .cancel, handler: { _ in result(false) }), UIAlertAction(title: L10n.yes, style: .default, handler: { _ in result(true) })]
        )
    }

    func showResetToBundleError() {
        self.showAlert(title: L10n.error, message: L10n.Errors.Translators.bundleReset, actions: [UIAlertAction(title: L10n.ok, style: .cancel, handler: nil)])
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
                guard let controller = self.conflictReceiverAlertController else {
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
                guard let controller = self.conflictAlertQueueController else {
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
                let (title, message, actions) = createAlert(for: conflict, completed: completed)

                let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                actions.forEach { action in
                    alert.addAction(action)
                }
                self.viewController?.present(alert, animated: true, completion: nil)

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
                                       UIAlertAction(title: L10n.Errors.Sync.keepChanges, style: .default, handler: { _ in
                            completed(.keepGroupChanges(.group(groupId)))
                        })]
                        return (L10n.warning, L10n.Errors.Sync.metadataWriteDenied(groupName), actions)

                    case .groupFileWriteDenied(let groupId, let groupName):
                        guard let webDavController = self.controllers.userControllers?.webDavController else { return ("", "", []) }

                        let domainName: String
                        if !webDavController.sessionStorage.isEnabled {
                            domainName = "zotero.org"
                        } else {
                            let url = URL(string: webDavController.sessionStorage.url)
                            if #available(iOS 16.0, *) {
                                domainName = url?.host() ?? ""
                            } else {
                                domainName = url?.host ?? ""
                            }
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
        let controller = UIAlertController(title: L10n.Settings.Sync.DirectoryNotFound.title, message: L10n.Settings.Sync.DirectoryNotFound.message(url), preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: L10n.cancel, style: .cancel, handler: { _ in cancel() }))
        controller.addAction(UIAlertAction(title: L10n.create, style: .default, handler: { _ in create() }))
        self.viewController?.present(controller, animated: true, completion: nil)
    }

    func askForPermission(message: String, completed: @escaping (DebugPermissionResponse) -> Void) {
        DispatchQueue.main.async {
            _askForPermission(message: message, completed: completed)
        }

        func _askForPermission(message: String, completed: @escaping (DebugPermissionResponse) -> Void) {
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
}

extension AppCoordinator: OpenItemsPresenter {
    func showItem(with presentation: ItemPresentation) {
        switch presentation {
        case .pdf(let library, let key, let url):
            showPDF(at: url, key: key, library: library)
        }
    }
    
    private func showPDF(at url: URL, key: String, library: Library) {
        guard let window, let mainController = window.rootViewController as? MainViewController else { return }
        mainController.getDetailCoordinator { [weak self] coordinator in
            guard let self else { return }
            let controller = coordinator.createPDFController(key: key, library: library, url: url)
            self.show(controller: controller, by: mainController, in: window, animated: false)
        }
    }
}

extension AppCoordinator: InstantPresenter {}
