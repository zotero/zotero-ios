//
//  SceneDelegate.swift
//  Zotero
//
//  Created by Michal Rentka on 09/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import UIKit

import CocoaLumberjackSwift

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    private var coordinator: AppDelegateCoordinatorDelegate!
    private weak var activityCounter: SceneActivityCounter?
    private var sessionCancellable: AnyCancellable?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let delegate = UIApplication.shared.delegate as? AppDelegate, let controllers = delegate.controllers else { return }

        let windowScene = scene as? UIWindowScene
        let frame = windowScene?.coordinateSpace.bounds ?? UIScreen.main.bounds

        // Assign activity counter
        activityCounter = delegate
        // Create window for scene
        let window = UIWindow(frame: frame)
        self.window = window
        window.windowScene = windowScene
        window.makeKeyAndVisible()
        // Load state if available, setup scene & window
        setup(scene: scene, userActivity: userActivity, window: window, options: connectionOptions, session: session, controllers: controllers)
        // Start observing
        setupObservers(options: connectionOptions, session: session, controllers: controllers)

        func setup(scene: UIScene, userActivity: NSUserActivity?, window: UIWindow, options connectionOptions: UIScene.ConnectionOptions, session: UISceneSession, controllers: Controllers) {
            scene.userActivity = userActivity
            scene.title = userActivity?.title

            // Setup app coordinator and present initial screen
            let coordinator = AppCoordinator(window: window, controllers: controllers)
            coordinator.start(options: connectionOptions, session: session)
            self.coordinator = coordinator
        }

        func setupObservers(options connectionOptions: UIScene.ConnectionOptions, session: UISceneSession, controllers: Controllers) {
            sessionCancellable = controllers.userInitialized
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { _ in },
                    receiveValue: { [weak self] result in
                        guard let self else { return }
                        let _isLoggedIn: Bool
                        switch result {
                        case .success(let isLoggedIn):
                            _isLoggedIn = isLoggedIn

                        case .failure:
                            _isLoggedIn = false
                        }
                        coordinator.showMainScreen(isLoggedIn: _isLoggedIn, options: connectionOptions, session: session, animated: false)
                    }
                )
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let delegate = UIApplication.shared.delegate as? AppDelegate, let urlController = delegate.controllers.userControllers?.customUrlController else { return }
        
        if let urlContext = URLContexts.first {
            let sourceApp = urlContext.options.sourceApplication ?? "unknown"

            DDLogInfo("SceneDelegate: App opened by \(urlContext.url.absoluteString) from \(sourceApp)")

            if let kind = urlController.process(url: urlContext.url) {
                coordinator.show(customUrl: kind, animated: (UIApplication.shared.applicationState == .active))
            }
        }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        if shortcutItem.type == NSUserActivity.mainId {
            completionHandler(coordinator.showMainScreen(with: .custom(.myLibrary), selectedCollection: .custom(.all)))
        }
        completionHandler(false)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        didUpdate previousCoordinateSpace: UICoordinateSpace,
        interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation,
        traitCollection previousTraitCollection: UITraitCollection
    ) {
        guard let newSize = windowScene.windows.first?.frame.size else { return }
        coordinator?.didRotate(to: newSize)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        scene.userActivity?.becomeCurrent()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        scene.userActivity?.resignCurrent()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        activityCounter?.sceneWillEnterForeground()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        activityCounter?.sceneDidEnterBackground()
    }

    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        return scene.userActivity
    }
}
