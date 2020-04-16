//
//  SceneDelegate.swift
//  Zotero
//
//  Created by Michal Rentka on 09/04/2020.
//  Copyright © 2020 Corporation for Digital Scholarship. All rights reserved.
//

import Combine
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    private var coordinator: AppCoordinator!
    private weak var activityCounter: SceneActivityCounter?
    private var sessionCancellable: AnyCancellable?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let delegate = UIApplication.shared.delegate as? AppDelegate else { return }

        let windowScene = scene as? UIWindowScene
        let frame = windowScene?.coordinateSpace.bounds ?? UIScreen.main.bounds

        // Assign activity counter
        self.activityCounter = delegate
        // Create window for scene
        self.window = UIWindow(frame: frame)
        self.window?.windowScene = windowScene
        self.window?.makeKeyAndVisible()
        // Setup app coordinator and present initial screen
        self.coordinator = AppCoordinator(window: self.window, controllers: delegate.controllers)
        self.coordinator.start()
        // Start observing
        self.setupObservers(controllers: delegate.controllers)
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        self.activityCounter?.sceneWillEnterForeground()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        self.activityCounter?.sceneDidEnterBackground()
    }

    private func setupObservers(controllers: Controllers) {
        self.sessionCancellable = controllers.sessionController.$isLoggedIn
                                                               .receive(on: DispatchQueue.main)
                                                               .dropFirst()
                                                               .sink { [weak self] isLoggedIn in
                                                                   self?.coordinator.showMainScreen(isLoggedIn: isLoggedIn)
                                                               }
    }
}
