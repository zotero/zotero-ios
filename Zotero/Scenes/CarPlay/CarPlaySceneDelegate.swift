//
//  CarPlaySceneDelegate.swift
//  Zotero
//
//  Created by Michal Rentka on 12.10.2026.
//  Copyright © 2026 Corporation for Digital Scholarship. All rights reserved.
//

import CarPlay

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var coordinator: CarPlayCoordinator?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        guard let delegate = UIApplication.shared.delegate as? AppDelegate, let controllers = delegate.controllers else { return }
        let coordinator = CarPlayCoordinator(interfaceController: interfaceController, controllers: controllers)
        coordinator.start()
        self.coordinator = coordinator
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        coordinator = nil
    }

    // The CarPlay scene counts as a foreground scene, so that sync keeps running while only CarPlay is in use.

    func sceneWillEnterForeground(_ scene: UIScene) {
        (UIApplication.shared.delegate as? SceneActivityCounter)?.sceneWillEnterForeground()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        (UIApplication.shared.delegate as? SceneActivityCounter)?.sceneDidEnterBackground()
    }
}
