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
        self.window = UIWindow(frame: frame)
        self.window?.windowScene = windowScene
        self.window?.makeKeyAndVisible()
        // Setup app coordinator and present initial screen
        let coordinator = AppCoordinator(window: self.window, controllers: delegate.controllers)
        coordinator.start()
        self.coordinator = coordinator
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
        self.sessionCancellable = controllers.userInitialized
                                             .receive(on: DispatchQueue.main)
                                             .sink(receiveCompletion: { _ in },
                                                   receiveValue: { [weak self] result in
                                                 switch result {
                                                 case .success(let isLoggedIn):
                                                     self?.coordinator.showMainScreen(isLoggedIn: isLoggedIn)
                                                 case .failure(let error):
                                                     self?.userInitializationFailed(with: error)
                                                 }
                                             })
    }

    private func userInitializationFailed(with error: Error) {
        self.coordinator.showMainScreen(isLoggedIn: false)
        self.coordinator.show(error: error)
    }
}
