//
//  AppDelegate.swift
//  Zotero
//
//  Created by Michal Rentka on 03/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import UIKit

import CocoaLumberjack
import SwiftUI

#if PDFENABLED
import PSPDFKit
#endif

protocol SceneActivityCounter: class {
    func sceneWillEnterForeground()
    func sceneDidEnterBackground()
}

class AppDelegate: UIResponder {
    var controllers: Controllers!
    private var foregroundSceneCount = 0

    // MARK: - Setups

    private func setupLogs() {
        #if DEBUG
        // Enable console logs only for debug mode
        DDLog.add(DDTTYLogger.sharedInstance)

        // Change to .info to enable server logging
        // Change to .warning/.error to disable server logging
        dynamicLogLevel = .info
        #else
        dynamicLogLevel = .off
        #endif
    }

    private func setupNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}

extension AppDelegate: SceneActivityCounter {
    func sceneDidEnterBackground() {
        self.foregroundSceneCount -= 1

        if self.foregroundSceneCount == 0 {
            self.applicationDidEnterBackground(UIApplication.shared)
        }
    }

    func sceneWillEnterForeground() {
        if self.foregroundSceneCount == 0 {
            self.applicationWillEnterForeground(UIApplication.shared)
        }

        self.foregroundSceneCount += 1
    }
}

extension AppDelegate: UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        #if PDFENABLED
        if let key = Licenses.shared.pspdfkitKey {
            PSPDFKit.setLicenseKey(key)
        }
        #endif

        self.setupLogs()
        self.controllers = Controllers()
        self.setupNavigationBarAppearance()

        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        self.controllers.didEnterBackground()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        self.controllers.willEnterForeground()
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        let controllers = self.controllers ?? Controllers()
        if let uploader = controllers.userControllers?.backgroundUploader {
            uploader.backgroundCompletionHandler = completionHandler
        } else {
            completionHandler()
        }
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
