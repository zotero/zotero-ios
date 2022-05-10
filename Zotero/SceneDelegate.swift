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
        guard let delegate = UIApplication.shared.delegate as? AppDelegate else { return }

        let windowScene = scene as? UIWindowScene
        let frame = windowScene?.coordinateSpace.bounds ?? UIScreen.main.bounds

        // Assign activity counter
        self.activityCounter = delegate
        // Create window for scene
        let window = UIWindow(frame: frame)
        self.window = window
        self.window?.windowScene = windowScene
        self.window?.makeKeyAndVisible()
        // Load state if available, setup scene & window
        let userActivity = connectionOptions.userActivities.first ?? session.stateRestorationActivity
        self.setup(scene: scene, window: window, with: userActivity, delegate: delegate)
        // Start observing
        self.setupObservers(controllers: delegate.controllers)
    }

    private func setup(scene: UIScene, window: UIWindow, with userActivity: NSUserActivity?, delegate: AppDelegate) {
        scene.userActivity = userActivity
        scene.title = userActivity?.title

        // Setup app coordinator and present initial screen
        let coordinator = AppCoordinator(window: self.window, controllers: delegate.controllers)
        coordinator.start(with: userActivity?.restoredStateData)
        self.coordinator = coordinator
    }

    func windowScene(_ windowScene: UIWindowScene, didUpdate previousCoordinateSpace: UICoordinateSpace, interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation, traitCollection previousTraitCollection: UITraitCollection) {
        guard let newSize = windowScene.windows.first?.frame.size else { return }
        self.coordinator?.didRotate(to: newSize)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        self.window?.windowScene?.userActivity?.becomeCurrent()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        self.window?.windowScene?.userActivity?.resignCurrent()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        self.activityCounter?.sceneWillEnterForeground()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        self.activityCounter?.sceneDidEnterBackground()
    }

    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        return scene.userActivity
    }

    private func setupObservers(controllers: Controllers) {
        self.sessionCancellable = controllers.userInitialized
                                             .receive(on: DispatchQueue.main)
                                             .sink(receiveCompletion: { _ in },
                                                   receiveValue: { [weak self] result in
                                                 switch result {
                                                 case .success(let isLoggedIn):
                                                     self?.coordinator.showMainScreen(isLoggedIn: isLoggedIn)
                                                 case .failure:
                                                     self?.coordinator.showMainScreen(isLoggedIn: false)
                                                 }
                                             })
    }
}
